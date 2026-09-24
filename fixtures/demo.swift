import SwiftUI

/* 秒览窗口 */
struct ContentView: View {
    @State private var name = "七帅"
    var body: some View {
        VStack(spacing: 12) {
            Text("你好，\(name)")
                .font(.title)
            Button("打招呼") {
                name = "世界" // 更新状态
            }
        }
    }
}
