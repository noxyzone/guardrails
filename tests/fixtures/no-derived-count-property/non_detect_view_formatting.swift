struct State: Equatable {
    var commits: [Commit] = []
}

struct CommitHistoryView: View {
    let model: Model

    var body: some View {
        Text("履歴（\(model.commits.count)件）")
    }
}
