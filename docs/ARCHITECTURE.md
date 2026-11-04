# 系统架构

## 信号链

```text
16 键矩阵 ─┐
串口屏触控 ─┼─> 输入归并/去抖 ─> 音色与八度控制 ─> 32 声部音频引擎
板载按键 ──┘                                      ├─ 钢琴算法合成
                                                ├─ 管风琴 ADPCM + 空间效果
                                                ├─ 二胡真实采样 + 延音循环
                                                └─ 古筝真实采样 + 自然衰减
                                                         │
                                                         v
                                              16 bit / I²S / 48.828 kHz
                                                         │
                                                         v
                                                    PCM5102A
```

## 主要模块

| 模块 | 作用 |
| --- | --- |
| `top_matrix_j13_pcm_screen` | 顶层连接、复位同步、外设和音频核心实例化 |
| `matrix_keyscan16` | 4×4 键盘行扫描、列采样和双边去抖 |
| `key_capture2` | 板载控制键的同步与去抖 |
| `tjc_hmi_rx` | 串口屏命令接收和输入事件解析 |
| `tjc_hmi_uart_tx` | 音量、电平、音符、页面和波形帧回传 |
| `touch_note_merge` | 屏幕音符/和弦掩码与矩阵按键合并 |
| `tjc_control_merge` | PC 与串口屏音量/增益控制的仲裁 |
| `keyboard_audio_core` | 音色路由、音频总线和 PCM5102A 输出控制 |
| `voice_engine_32` | 钢琴算法合成、32 声部分配、ADSR 与混音 |
| `sample_sampler` | 二胡/古筝八组采样、音域映射、循环和增益 |
| `organ_sampler` | 五组管风琴采样和 16 声部渲染 |
| `organ_room` | 管风琴空间效果和尾音 |
| `i2s_pcm5102_stream` | PCM5102A I²S 时序和 4 倍子帧插值 |
| `pt8211_stream` | 音频核心源帧时序、欠载检测和静音暂停 |
| `keyboard_status_uart` | 调试串口状态和波形遥测 |

## 音色路由

`keyboard_audio_core` 对音色编号作如下选择：

- `0`：原有钢琴算法引擎；
- `1`：`sample_sampler` 的二胡 bank 0–3；
- `2`：`organ_sampler` 和 `organ_room`；
- `3`：`sample_sampler` 的古筝 bank 4–7。

钢琴和管风琴路径保持独立。二胡与古筝共享采样器硬件，但使用不同的根音组、循环策略和音区增益。

## 音频采样实现

- 每个 bank 为 8192 个 16 bit 字，每个字含 4 个 IMA ADPCM nibble。
- 二胡 root：C4、E4、G4、A4，使用匹配循环延音。
- 古筝 root：C4、G4、D5、G5，保留自然衰减，不做强制延音循环。
- 古筝高音 bank 使用 Q7 增益补偿。
- 音高换算以 13 kHz 源率和约 48.828 kHz 输出帧率为基准。

## 时钟与复位

- `sys_clk`：50 MHz，约束周期 20 ns。
- 复位输入 `rst_n` 经三级同步后释放内部逻辑。
- 音频按帧分时复用 32 个声部；串口屏更新使用 1 kHz tick 和限速帧发送，避免音频状态机被长时间占用。

