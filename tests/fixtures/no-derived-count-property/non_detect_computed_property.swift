struct State: Equatable {
    var commits: [Commit] = []

    var commitCount: Int {
        commits.count
    }
}
