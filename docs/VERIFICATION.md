# 验证记录

## 参考固件

- 文件：`firmware/reference/J13_Piano_Realistic_Erhu_Guzheng_Organ_NoWM.fs`
- 曾通过 Gowin Programmer 外部 Flash Erase、Program、Verify；
- 工具成功标志：`Program and Verify Flash successfully.`
- 参考 SHA-256 记录于根目录 `SHA256SUMS.txt`。

## 源码干净重编译

- 从提交目录中的分类 RTL、include、ADPCM 数据和约束独立构建；
- Gowin Synthesis、Place & Route、Timing Analysis 和 Bitstream Generation 全部完成；
- 构建日志：`evidence/reports/source_rebuild.log`；
- 布局布线报告：`evidence/reports/source_rebuild_pnr_report.txt`；
- 时序路径：`evidence/reports/source_rebuild_timing_paths.txt`；
- 重编译固件：`firmware/rebuilt_from_source/XinLiYin_J13_SourceRebuild.fs`。

当前源码重编译资源占用：

| 资源 | 使用量 | 利用率 |
| --- | ---: | ---: |
| Logic | 27209/59904 | 46% |
| Register | 14740/60780 | 25% |
| BSRAM | 93/118 | 79% |
| DSP | 17/118 | 15% |

时序报告显示 20 ns 系统时钟路径存在正 setup slack；具体数值以报告文件为准。

## 音频数据校验

`tools/sample_pipeline/verification.json` 对每个 bank 解码后检查：

- ADPCM 峰值和 RMS；
- 二胡循环接缝处的跳变；
- 与相邻正常波形跳变的比较；
- 100 ms 尾部淡出和采样边界。

二胡循环相关度约 0.91–0.98；古筝 bank 不使用人造持续循环。

## 验证边界

本提交包验证的是源码构建、资源、约束、时序、位流生成、ADPCM 离线解码和已有烧录记录。以下项目仍需实机或仪器确认：

- 最终声压、频响、噪声和失真；
- 不同 PCM5102A 模块的模拟输出差异；
- 串口屏线缆、分压和接地质量；
- 用户实际按键手感与主观音色评价。

