import SwiftUI

struct HelpView: View {
    @State private var showKeyMap: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header

                Button(action: { showKeyMap = true }) {
                    Label("查看 FPGA 键位对照", systemImage: "keyboard")
                }
                .buttonStyle(
                    PixelFilledButtonStyle(
                        fontSize: 13,
                        horizontalPadding: 14,
                        verticalPadding: 8
                    )
                )

                HelpSection(
                    title: "首页与返回",
                    detail: "双页布局：首页选择自由演奏、三个音游、纸上舞台、蓝牙连接、使用说明。右上角版本号与连接状态始终可见；练习页面返回首页会释放正在进行的演奏。"
                )

                HelpSection(
                    title: "音源模式：iPad本地声音 / FPGA音箱",
                    detail: "顶部明确显示当前音源。iPad本地声音使用 App 内合成音色，不控制 FPGA；FPGA音箱只负责发送演奏事件，本地发声停止。同一次有效 BLE 连接中选择 FPGA音箱后，返回首页再进入自由演奏会保留选择；离开页面仍会释放所有 BLE 音符、踏板和表情。重新进入时会先恢复八度、品位、掌根、阻尼等 App 目标，再接受触摸。BLE 断线或能力失效会回退到 iPad本地声音。"
                )

                HelpSection(
                    title: "钢琴：16 键与八度",
                    detail: "白键 A–L、黑键 Z–M 对应协议 KEY 0–15。本地模式可用低/原/高八度。FPGA v2 音源下先发送八度目标 0x30，再发送按下 0x01；每次按键都带当前 App 八度，界面显示“FPGA八度目标”。FPGA v1 不声明八度，八度控件禁用，硬件使用默认。"
                )

                HelpSection(
                    title: "钢琴：阻尼与踏板",
                    detail: "阻尼 0x31 开启时，BLE 松键请求释放；关闭时让声音自然衰减。踏板 0x32 在阻尼开启时延迟 BLE 松键释放；松开踏板发送 0x32=0 并发送 0x33 释放待处理音。触摸取消、离开页面和后台会清空长音与踏板状态。阻尼关闭时踏板控件不生效。"
                )

                HelpSection(
                    title: "吉他：0–12 品、六弦和和弦",
                    detail: "六弦 Q/W/E/R/T/Y = E2/A2/D3/G3/B3/E4。每次拨弦组内先发送品位 0x21、掌根 0x22，再发送拨弦 0x20（弦编号 + 力度）。四个和弦 C/G/Dm/Am 用 U/I/O/P 按钮，一次按下按顺序发送选择 0x23 + 触发 0x24。和弦是硬件既有短促一次性模式：松手不会立即制音，不显示为持续按住。"
                )

                HelpSection(
                    title: "吉他：表情面板",
                    detail: "点“表情”打开面板。掌根闷音是 0/1 目标。弯音只有左 -2、回中、右 +2 三个端点，按住左右键，松手/滑出/取消/关闭面板回中，不提供连续弯音滑杆。颤音是固定频率/深度的开关。滑音开关开启时，品位目标可作用于当前主奏，不会通过重复拨弦模拟滑音。滑音时间 1–15 档，每档 20ms，显示 20–300ms。"
                )

                HelpSection(
                    title: "吉他：共享过载与混响",
                    detail: "过载 0x2A 和混响 0x2B 是共享吉他效果链，发送明确的 0/1 目标，不会“再切换”。CAPS 只回报能力和错误标志，不回报效果当前值，因此界面只显示 App 目标，不显示“FPGA 已确认”。重新进入页面不会自动重发这两个共享目标，避免覆盖实体键盘刚设定的效果；需要改变时请在面板中明确选择。"
                )

                HelpSection(
                    title: "九鼓与正确编号",
                    detail: "九宫格使用小键盘 1–9。BLE 逻辑编号按协议：Kick=0、Snare=1、ClosedHat=2、OpenHat=3、Ride=4、Crash=5、HighTom=6、LowTom=7、MidTom=8。特别是 Ride 不能发成 Crash，Mid Tom 不能与 Low Tom 交换。鼓为一次性触发；闭镲 choke 由 FPGA 执行。"
                )

                HelpSection(
                    title: "BLE 能力：v1 与 v2",
                    detail: "连接通知成功后 App 自动发送 E1 00。旧版回复 FPGA_STATUS;1;… 选择 v1 基础功能；新版 CAPS;2;<8位掩码>;… 按实际 32 位能力逐项开放。未知版本、字段异常、status 保留位异常或零能力掩码会显示明确原因，不开放 FPGA 音箱。PONG/FPGA_PONG 只说明链路，不会开放演奏。"
                )

                HelpSection(
                    title: "Capability mask 说明",
                    detail: "bit0 钢琴、bit1 九鼓、bit2 吉他拨弦、bit3 和弦、bit4 品位、bit5 掌根、bit6 弯音/颤音、bit7 滑音/滑时、bit8 过载、bit9 混响、bit10 钢琴八度、bit11 阻尼/踏板、bit12 全部释放、bit13 全局停止、bit14 会话/心跳、bit15 查询。未声明的控件禁用；app 不把全置位掩码解释成未定义功能。"
                )

                HelpSection(
                    title: "释放、后台与断线",
                    detail: "E0 05 释放 BLE 音符、待处理踏板音、BLE 和弦触发和连续表情；E0 06 是独立全局停止。离开页面、切模式、后台会清理弦音、踏板、弯音、颤音和滑音；全局停止按钮单独发送 E0 06。BLE 断线由 ESP/FPGA 兜底；App 断线后会回到本地音源，不重放旧音符。"
                )

                HelpSection(
                    title: "本地音量与硬件音量",
                    detail: "顶部音量滑杆只控制 iPad本地音色。当前硬件协议没有总音量控制命令；切到 FPGA音箱后滑杆禁用并标注“本地音量/硬件无命令”，不会把本地音量伪装成 FPGA 音箱音量。"
                )

                HelpSection(
                    title: "音游与纸上舞台",
                    detail: "电吉他音游、架子鼓音游、钢琴音游和纸上舞台的练习/判定/乐器插画动画均保留。三个音游共享根级 BLE、能力门槛和发送队列，可在各自页面顶部选择“iPad本地声音 / FPGA音箱”；真实触摸琴键、弦、品位、和弦或鼓垫才发送演奏事件，谱面/插画/判定动画不会自动发声。"
                )

                HelpSection(
                    title: "音游的 FPGA 能力要求",
                    detail: "钢琴音游使用钢琴按下/释放（v1 即可，固定原八度）；架子鼓音游使用九鼓（v1/v2）；吉他音游需要 v2 的吉他拨弦、品位和和弦，v1 回退时自动使用 iPad本地声音并显示缺口。三个音游都使用真实触摸触发，吉他先发品位/和弦参数再拨弦，钢琴严格按下/释放，鼓使用正确映射与力度。"
                )

                HelpSection(
                    title: "音游页面生命周期",
                    detail: "暂停、重开、返回、触摸滑出/取消、进入后台或 BLE 断线都会释放本页面持有的音符和发送状态；不会重放旧谱面事件，也不会用判定重复触发声音。离开页面保留同一有效连接下的音源模式，但释放本页演奏状态。"
                )

                HelpSection(
                    title: "钢琴长按与连击反馈",
                    detail: "钢琴谱面含短音和长按：长条有头、身体和尾；头到判定线时按下，保持到尾再松。提前松手会断连，尾部有明确早晚容差；长按只发一次 NOTE_ON，真实松手发 NOTE_OFF，声音仍按硬件包络自然衰减，不承诺无限等响。普通命中会亮键、判定线短波纹和少量纸屑粒子；10/25/50 连击有数字弹出、背景光晕和短震动，震动只作用于视觉，触摸区不变。可点“降低动效”关闭强震动/粒子。"
                )

                HelpSection(
                    title: "架子鼓视觉提示",
                    detail: "九个鼓垫之间保留约 10–14pt 留白和完整触摸面积。提示不再使用缩小的矩形，而是鼓垫自身底色和边框随接近节拍变亮，到拍高亮，击中短暂显示判定颜色，漏击轻微变暗后恢复；提示严格按鼓号和实际鼓映射绑定，不会用数组下标代替。高亮和文字裁剪在各自鼓垫内，多鼓独立；视觉层不拦截触摸，也不会重复触发鼓声。"
                )

                HelpSection(
                    title: "吉他简化、完整品位与慢速",
                    detail: "默认谱面以空弦和同一品位为主，换品只放在乐句间有准备时间的位置，末尾保留四个和弦；不自动切换用户选择的品位。常用 0/2/3/5 品可快速点选，完整 0–12 品在可展开面板中。慢速 0.75× 会同时改变谱面时间、判定、插画/音符动画和结果计时，使用同一个时间系数；不是只减慢插画。真实触弦仍先发品位/掌根参数，再发拨弦；和弦音先选择和弦再触发。"
                )

                HelpSection(
                    title: "音乐厅与完整歌曲包",
                    detail: "音乐厅区分在线曲目、下载到 iPad 的本地包和 FPGA 设备侧缓存。下载会校验 HTTP/文件大小/整包 SHA-256、ZIP 路径/大小/成员白名单、manifest 文件摘要、FPGS 头/事件数/CRC 和必要能力；Files 可导入 .fpgasong。下载进度与 iPad→ESP 传输进度分开显示。没有真实在线地址时不伪造下载完成；静音舞台预览不等于本地音频或 FPGA 声音。"
                )

                HelpSection(
                    title: "音乐厅播放与设备门禁",
                    detail: "本版按 MUSIC_HALL_PROTOCOL_V1 接入 ESP v0.5：E2 CAPS/BEGIN/DATA/COMMIT/PREPARE/PLAY/STOP，校验 STATUS/ERROR；只上传 performance.bin。播放页段落、乐手动作和灯光不由动画帧触发音符。该候选没有硬件 progress，FPGA 演奏时间轴明确标注为估算动画，不代表设备位置。暂停、seek、远程音量没有实现，不开放。"
                )

                HelpSection(
                    title: "当前硬件验收边界",
                    detail: "ESP v0.5 与 music-hall-v1 候选 FPGA 已有实现，但尚未完成 iPad 编译、真实 BLE 上传、三乐器整曲播放和板级听感验收。实际包为 fpgasong 1.0（score/ 子目录），App 已支持安全路径与目录结构；pack 下载/导入/校验、局域网服务器下载和 PC 侧校验通过，但不能把静态检查或 PC 下载测试当作 iPad/硬件播放通过。"
                )

                HelpSection(
                    title: "版本与回退",
                    detail: "本版 v0.15.8。可直接回退 v0.13.0/v0.12.0（v0.14.1 保留修复但没有真实 transport；v0.14.0 有状态机问题）；基础回退 v0.10.2 + 旧 ESP v0.3/基础 BLE FPGA。v0.10.2 只识别 FPGA_STATUS v1，不能用于 CAPS v2/v3 固件；基础旧 BLE 硬件回退与 expression 候选分开验收。"
                )

                Text("版本 \(AppInfo.versionLabel) · \(FPGAKeyMap.localPreviewNote)")
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundStyle(PixelPalette.muted)
                    .padding(.bottom, 6)
            }
            .padding(18)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showKeyMap) {
            KeyMapReferenceSheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("使用说明")
                .font(.system(size: 30, weight: .heavy, design: .serif))
                .foregroundStyle(PixelPalette.ink)
            Text("\(AppInfo.touchModeLabel) · \(AppInfo.deviceLabel) · \(AppInfo.bluetoothLabel)")
                .font(.system(size: 12, weight: .medium, design: .serif))
                .foregroundStyle(PixelPalette.muted)
            Text(FPGAKeyMap.sourceNote)
                .font(.system(size: 9, weight: .regular, design: .serif))
                .foregroundStyle(PixelPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 2)
    }
}

private struct HelpSection: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .foregroundStyle(CosmicPalette.paperInk)
            Text(detail)
                .font(.system(size: 12, weight: .regular, design: .serif))
                .foregroundStyle(CosmicPalette.paperInk.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cosmicPaperCard()
    }
}


