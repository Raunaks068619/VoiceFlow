import Foundation

@main
struct PolishFormattingPolicyRegression {
    private static var failures: [String] = []

    static func main() {
        let enabledInstruction = PolishFormattingPolicy.structureInstruction(isEnabled: true)
        let disabledInstruction = PolishFormattingPolicy.structureInstruction(isEnabled: false)
        let naturalTaskList = """
        I want to:

        - Create a gym plan.
        - Log each exercise.
        - Post one video per week.
        - Create a UGC ad.
        """
        let orderedSteps = """
        1. Open the project.
        2. Run the tests.
        3. Ship the build.
        """

        expect(
            enabledInstruction.contains("MUST become a hyphen-bulleted list"),
            "enabled prompt must require bullets for natural multi-item speech"
        )
        expect(
            enabledInstruction.contains("MUST become a numbered list"),
            "enabled prompt must require numbering for explicit sequences"
        )
        expect(
            disabledInstruction.contains("Do not introduce bullets"),
            "disabled prompt must prohibit inferred lists"
        )
        expect(
            !PolishFormattingPolicy.outputContract.lowercased().contains("no markdown, code fences, bullets"),
            "shared output contract must not prohibit valid bullets"
        )
        expect(
            PolishFormattingPolicy.containsStructuredList(naturalTaskList),
            "bullet output must be recognized as structured"
        )
        expect(
            PolishFormattingPolicy.containsStructuredList(orderedSteps),
            "numbered output must be recognized as structured"
        )
        expect(
            PolishFormattingPolicy.allowsStructuredLists(
                processingModeRawValue: "dictation",
                structureRuleEnabled: true
            ),
            "Polish mode must allow lists when structure is enabled"
        )
        expect(
            !PolishFormattingPolicy.allowsStructuredLists(
                processingModeRawValue: "dictation",
                structureRuleEnabled: false
            ),
            "Polish mode must not infer lists when structure is disabled"
        )
        expect(
            !PolishFormattingPolicy.rejectsStructuredList(
                naturalTaskList,
                allowStructuredLists: true
            ),
            "valid structured Polish output must pass the guard"
        )
        expect(
            PolishFormattingPolicy.rejectsStructuredList(
                naturalTaskList,
                allowStructuredLists: false
            ),
            "unsolicited structured output must fail when structure is disabled"
        )

        if failures.isEmpty {
            print("✅ Polish formatting policy regression checks passed")
            return
        }

        failures.forEach { print("❌ \($0)") }
        exit(1)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }
}
