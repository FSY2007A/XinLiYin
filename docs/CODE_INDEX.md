# 代码文件索引

## 最终固件活动源码

以下文件参与当前 `top_matrix_j13_pcm_screen` 构建。

| 文件 | 分类 | 说明 |
| --- | --- | --- |
| `rtl/top/top_matrix_j13_pcm_screen.v` | 顶层 | 系统端口、复位同步和模块连接 |
| `rtl/audio/keyboard_audio_core.v` | 音频 | 音色路由、主音量、PCM5102A 输出 |
| `rtl/audio/voice_engine_32.v` | 音频 | 32 声部混音与算法合成 |
| `rtl/audio/sample_sampler.v` | 音频 | 二胡/古筝 ADPCM 多根音采样器 |
| `rtl/audio/organ_sampler.v` | 音频 | 管风琴 ADPCM 采样器 |
| `rtl/audio/organ_room.v` | 音频 | 管风琴空间效果 |
| `rtl/audio/i2s_pcm5102_stream.v` | 音频 | PCM5102A I²S 发送 |
| `rtl/audio/pt8211_stream.v` | 音频 | 源帧率、插值和欠载检测 |
| `rtl/support/sine_rom.v` | 音频支持 | 1024 点正弦波表 |
| `rtl/support/string_sample_rom.v` | 兼容 | 可配置光谱/弦乐 ROM 接口 |
| `interaction/rtl/matrix_keyscan16.v` | 交互 | 4×4 矩阵扫描和去抖 |
| `interaction/rtl/key_capture2.v` | 交互 | 板载按键捕获 |
| `interaction/rtl/tjc_hmi_rx.v` | 交互 | HMI 串口命令解析 |
| `interaction/rtl/tjc_hmi_uart_tx.v` | 交互 | HMI 状态与波形发送 |
| `interaction/rtl/touch_note_merge.v` | 交互 | 屏幕与矩阵音符合并 |
| `interaction/rtl/tjc_control_merge.v` | 交互 | 音量/增益控制仲裁 |
| `interaction/rtl/keyboard_status_uart.v` | 调试 | PC 状态与波形遥测 |

## 编译期数据

| 文件 | 说明 |
| --- | --- |
| `include/sample_metadata.vh` | 二胡/古筝 bank、根音、循环与步进 |
| `include/organ_metadata.vh` | 管风琴音色元数据 |
| `include/organ_steps.vh` | IMA ADPCM step table |
| `include/animation_layout.vh` | HMI 波形和数字字形布局 |
| `data/instrument_samples/sample_adpcm_0..7.mem` | 二胡 bank 0–3、古筝 bank 4–7 |
| `data/organ/organ_adpcm_0..4.mem` | 管风琴五组 ADPCM |

## 交互界面与协议

| 文件 | 说明 |
| --- | --- |
| `interaction/ui/final/ture1.HMI` | 当前指定的正式串口屏工程 |
| `interaction/ui/archive/tune_screen_keys.HMI` | 历史界面版本 |
| `interaction/ui/archive/tune_original_backup.HMI` | 原始界面备份 |
| `interaction/docs/INTERACTION_SYSTEM.md` | 界面、触控、串口和输入合并说明 |

## 构建与约束

| 文件 | 说明 |
| --- | --- |
| `build/build.tcl` | 可迁移 Gowin 构建脚本 |
| `build/rebuild.ps1` | Windows 构建包装 |
| `constraints/matrix_j13_pcm_screen.cst` | 最终引脚约束 |
| `constraints/mega60k.sdc` | 20 ns 系统时钟约束 |

## 兼容与历史参考

`reference/` 中的上弦、吉他、旧顶层和历史数据不参与当前顶层。保留原因：

- 保证可追溯旧实验；
- 支持以后重新启用 `BOWED_STRINGS`、`STRING_SAMPLE` 或吉他配置；
- 避免把未参与最终作品的代码误认为当前功能。

## 生成工具

| 文件 | 说明 |
| --- | --- |
| `tools/sample_pipeline/build_realistic_banks.py` | 二胡/古筝 WAV/FLAC → ADPCM bank |
| `tools/sample_pipeline/verify_generated_banks.py` | ADPCM 解码、循环和预览校验 |
| `tools/sample_pipeline/manifest.json` | 采样生成参数与源路径 |
| `tools/sample_pipeline/verification.json` | 离线验证结果 |

