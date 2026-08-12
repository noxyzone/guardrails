struct State: Equatable {
    var commits: [Commit] = []
}

struct Feature: Reducer {
    func reduce(into state: inout State, action: Action) -> Effect<Action> {
        let commitCount = state.commits.count
        print(commitCount)
        return .none
    }
}
