#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$ROOT_DIR/scripts/gitleaks-check.sh"
FIXTURE="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE"' EXIT

command -v gitleaks >/dev/null || {
    echo "FAIL: gitleaks is required for this real-tool test" >&2
    exit 1
}
gitleaks_version="$(gitleaks version)"
[[ "$gitleaks_version" == "8.30.1" ]] || {
    echo "FAIL: gitleaks version must be 8.30.1, got $gitleaks_version" >&2
    exit 1
}

git -C "$FIXTURE" init -q

# Dummy values only. These are not real credentials. Parts are joined while
# generating fixtures so this test source is not itself a gitleaks finding.
printf 'aws_access_key_id = %s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' >"$FIXTURE/positive-aws.txt"
printf '%s%s\n%s\n%s%s\n' '-----BEGIN ' 'PRIVATE KEY-----' \
    'MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7' \
    '-----END ' 'PRIVATE KEY-----' >"$FIXTURE/positive-private-key.txt"
printf 'token = %s%s\n' 'glpat-' 'abcdefghijklmnopqrstuvwxyz12' >"$FIXTURE/positive-gitlab-pat.txt"
printf 'slack_token = %s%s%s\n' 'xoxb-' '123456789012-123456789012-' \
    'abcdefghijklmnopqrstuvwx' >"$FIXTURE/positive-slack.txt"

# Negatives: documentation, official AWS example key, and incomplete tokens.
printf 'aws_access_key_id = %s\n' 'AKIAIOSFODNN7EXAMPLE' >"$FIXTURE/negative-aws-example.txt"
printf '%s\n' 'docs: set AWS_ACCESS_KEY_ID in the environment' >"$FIXTURE/negative-env-docs.txt"
printf '%s\n' 'https://github.com/example/repo.git' >"$FIXTURE/negative-github-url.txt"
printf '%s\n' 'test_password = "x"' >"$FIXTURE/negative-short-password.txt"

# SecretLint recommendで検出していた代表値を、追加gitleaksルールでも維持する。
printf 'npm_token = %s%s\n' 'npm_' 'abcdefghijklmnopqrstuvwxyz0123456789' >"$FIXTURE/delta-npm-token.txt"
printf 'github_token = %s%s\n' 'ghp_' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    >"$FIXTURE/delta-github-pat-low-entropy.txt"
printf 'password = "%s%s"\n' 'supersecret' 'value' >"$FIXTURE/delta-password-assignment.txt"

git -C "$FIXTURE" add -- .
run_list() {
    local list_file="$1"
    "$CHECK_SCRIPT" --files-from "$list_file" --repo "$FIXTURE"
}

printf '%s\n' positive-aws.txt >"$FIXTURE/positive-aws.list"
if run_list "$FIXTURE/positive-aws.list"; then
    echo "FAIL: gitleaks must detect dummy AWS access key" >&2
    exit 1
fi
printf '%s\n' positive-private-key.txt >"$FIXTURE/positive-key.list"
if run_list "$FIXTURE/positive-key.list"; then
    echo "FAIL: gitleaks must detect dummy private key" >&2
    exit 1
fi
printf '%s\n' positive-gitlab-pat.txt >"$FIXTURE/positive-gitlab.list"
if run_list "$FIXTURE/positive-gitlab.list"; then
    echo "FAIL: gitleaks must detect dummy GitLab PAT" >&2
    exit 1
fi
printf '%s\n' positive-slack.txt >"$FIXTURE/positive-slack.list"
if run_list "$FIXTURE/positive-slack.list"; then
    echo "FAIL: gitleaks must detect dummy Slack token" >&2
    exit 1
fi

printf '%s\n' negative-aws-example.txt negative-env-docs.txt negative-github-url.txt negative-short-password.txt >"$FIXTURE/negatives.list"
run_list "$FIXTURE/negatives.list" || {
    echo "FAIL: gitleaks must not flag negative dummy fixtures" >&2
    exit 1
}

for delta_fixture in delta-npm-token.txt delta-github-pat-low-entropy.txt delta-password-assignment.txt; do
    printf '%s\n' "$delta_fixture" >"$FIXTURE/delta.list"
    if run_list "$FIXTURE/delta.list"; then
        echo "FAIL: gitleaks must preserve SecretLint detection for $delta_fixture" >&2
        exit 1
    fi
done

# 固定文書のSHA-256だけを許可し、未知値と前後への付加は許可しない。
known_digests=(
    620b23af1e7f31d6714a6340b3267387f2d5f110d231cbca5b25ee34ea0397e5
    1d500c9d2419e7acca57e17fa46a7523ec0d248fb63f3c285d32653d12956753
    ecb567dc2291f78288811461987449b3987f45bfb7fa6d63527300f09f00681f
)
printf '%s\n' document-digest.json >"$FIXTURE/digest.list"
for digest in "${known_digests[@]}"; do
    printf '{"api": "%s"}\n' "$digest" >"$FIXTURE/document-digest.json"
    if ! run_list "$FIXTURE/digest.list" >"$FIXTURE/digest.log" 2>&1; then
        echo "FAIL: known document digest must not be treated as a credential" >&2
        exit 1
    fi
    for modified_digest in "0$digest" "${digest}0" "${digest%?}0"; do
        printf '{"api": "%s"}\n' "$modified_digest" >"$FIXTURE/document-digest.json"
        if run_list "$FIXTURE/digest.list" >"$FIXTURE/digest.log" 2>&1; then
            echo "FAIL: digest allowlist must use exact values only" >&2
            exit 1
        fi
    done
    # 許可値と同じファイルに置いた別の秘密情報も検出する。
    printf '{"api": "%s"}\n' "$digest" >"$FIXTURE/document-digest.json"
    cat "$FIXTURE/positive-aws.txt" >>"$FIXTURE/document-digest.json"
    if run_list "$FIXTURE/digest.list" >"$FIXTURE/digest.log" 2>&1; then
        echo "FAIL: known digest must not exempt other findings in the file" >&2
        exit 1
    fi
done

# 公式moduleの公開Sum1件だけを許可し、近似値や同じfileの秘密は拒否する。
# 出典: golang.org/x/oauth2@v0.35.0の正規module metadataとcacheの一致。
known_module_sum='h1:Mv2mzuHuZuY2+bkyWXIHMfhNdJAdwW3FuWeCPYN5GVQ='
module_digest="${known_module_sum#h1:}"
printf '%s\n' go.sum >"$FIXTURE/module-sum.list"
printf 'golang.org/x/oauth2 v0.35.0 %s\n' "$known_module_sum" >"$FIXTURE/go.sum"
if ! run_list "$FIXTURE/module-sum.list" >"$FIXTURE/module-sum.log" 2>&1; then
    echo "FAIL: verified public module Sum must not be treated as a credential" >&2
    exit 1
fi
# padding後の文字は既定ルールでも非検出となるため、paddingを末尾に保って付加する。
for modified_sum in "h1:0$module_digest" "h1:${module_digest%=}0=" "h1:N${module_digest:1}"; do
    printf 'golang.org/x/oauth2 v0.35.0 %s\n' "$modified_sum" >"$FIXTURE/go.sum"
    if run_list "$FIXTURE/module-sum.list" >"$FIXTURE/module-sum.log" 2>&1; then
        echo "FAIL: module Sum allowlist must reject prefixes, suffixes and near values" >&2
        exit 1
    fi
done
printf 'golang.org/x/oauth2 v0.35.0 %s\n' "$known_module_sum" >"$FIXTURE/go.sum"
cat "$FIXTURE/positive-aws.txt" >>"$FIXTURE/go.sum"
if run_list "$FIXTURE/module-sum.list" >"$FIXTURE/module-sum.log" 2>&1; then
    echo "FAIL: public module Sum must not exempt another credential in the same file" >&2
    exit 1
fi

echo "PASS"
