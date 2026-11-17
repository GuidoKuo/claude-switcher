import Foundation
import AppKit
@main struct RouterRealModel {
    static func main() {
        guard CommandLine.arguments.count == 3 else { exit(2) }
        let defaults = UserDefaults(suiteName: "router-real-model-\(UUID().uuidString)")!
        let vm = VM(core: CommandLine.arguments[1], checkTimeout: 20, noticeDefaults: defaults)
        vm.start()
        let deadline = Date().addingTimeInterval(25)
        while vm.isBusy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        if vm.isBusy { fputs("model timed out\n", stderr); exit(1) }
        if CommandLine.arguments[2] == "ready" {
            guard vm.phase == .ready, vm.lastCheckSummary == "有警告" else {
                fputs("not ready: \(vm.banner) \(vm.lastCheckSummary)\n", stderr); exit(1)
            }
        } else {
            guard vm.phase == .failed, vm.banner.contains("网关或接口") else {
                fputs("missing failure reason: \(vm.banner)\n", stderr); exit(1)
            }
        }
        print("PASS real core model \(CommandLine.arguments[2])")
    }
}
