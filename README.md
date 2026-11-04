# 芯力音：FPGA 智能键盘演奏作品代码提交包

提交版本：2026-11-03  
目标硬件：Tang Mega 60K，GW5AT-LV60PG484AC1/I0（GW5AT-60B）  
最终顶层：`top_matrix_j13_pcm_screen`

## 作品概述

芯力音是一套基于 FPGA 的实时数字乐器作品。作品使用 16 键矩阵和 TJC 串口触控屏完成输入与交互，以 GW5AT-60B 内部硬件逻辑实现按键扫描、32 声部音频引擎、音色切换和包络处理，并通过 I²S 接口将数字音频送入 PCM5102A。作品包含钢琴、二胡、古筝和管风琴四种音色。

本提交包同时包含：

- 最终参考固件和从源码重新编译的固件；
- 完整、可重编译的 Verilog RTL；
- 音频采样、ADPCM 数据表和生成/校验脚本；
- 交互界面工程 `ture1.HMI`；
- 串口触控协议、键盘扫描和显示控制 RTL；
- 引脚约束、时序约束和构建脚本；
- 综合、布局布线、资源、时序和烧录证据；
- 第三方素材的归属和许可文件。

## 目录说明

| 目录 | 内容 |
| --- | --- |
| `firmware/reference` | 用户指定并曾用于外部 Flash 烧录的参考固件 |
| `firmware/rebuilt_from_source` | 从本提交包源码干净重编译得到的固件 |
| `rtl/top` | 最终顶层 |
| `rtl/audio` | 32 声部引擎、乐音采样器、管风琴、I²S/PCM5102A 输出 |
| `rtl/support` | 可配置音频引擎使用的正弦表和兼容 ROM |
| `interaction/rtl` | 矩阵扫描、按键去抖、串口屏收发、触控/控制合并和状态回传 |
| `interaction/ui/final` | 最终交互界面工程 `ture1.HMI` |
| `interaction/ui/archive` | 先前使用的 HMI 版本，仅作版本追溯 |
| `interaction/docs` | 交互架构、串口协议和界面说明 |
| `include` | 编译期包含的采样元数据和界面布局表 |
| `data/instrument_samples` | 二胡、古筝 IMA ADPCM 采样数据 |
| `data/organ` | 管风琴 IMA ADPCM 采样数据 |
| `constraints` | 最终 CST 引脚约束和 SDC 时钟约束 |
| `build` | 可迁移的 Gowin Tcl 构建脚本和 PowerShell 包装脚本 |
| `tools/sample_pipeline` | 真实乐器采样生成、循环匹配和 ADPCM 校验脚本 |
| `evidence/reports` | 构建、布局布线、时序和引脚报告 |
| `reference` | 未参与最终固件的旧上弦/吉他模块和数据，仅作兼容追溯 |
| `THIRD_PARTY_LICENSES` | 第三方素材许可与署名 |
| `docs` | 架构、引脚、构建、验证和素材说明 |

## 快速构建

要求 Gowin EDA V1.9.12.03 或兼容版本。

```powershell
cd .\build
.\rebuild.ps1
```

也可直接运行：

```powershell
cd .\build
& "C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe" "build.tcl"
```

构建脚本会把分类源码暂存到 `build/_work/src`，以兼容 Gowin 对 `include` 和 `$readmemh` 的源文件目录查找规则。`build/_work` 是生成目录，不属于提交源码。

## 版本与一致性

- `firmware/reference/J13_Piano_Realistic_Erhu_Guzheng_Organ_NoWM.fs` 是用户指定、且曾通过外部 Flash 写入/校验的固件。
- 当前源码在参考固件生成后增加了一处声部循环状态重载修正，因此重新编译得到的哈希与参考固件不同。
- 两个固件的 SHA-256 均记录在根目录 `SHA256SUMS.txt`。
- 当前源码已经通过独立干净重编译、布局布线和时序分析。
- 本次整理未重新烧录“源码重编译固件”，上板验收结论仍以参考固件和已有实机记录为准。

## 重要配置

- 系统时钟：50 MHz
- 音频主帧率：约 48.828 kHz，I²S 4 倍子帧发送
- 音频位宽：16 bit
- 声部数：32
- 音色编号：0 钢琴、1 二胡、2 管风琴、3 古筝
- 二胡/古筝采样源率：13 kHz，IMA ADPCM
- 屏幕串口：115200 baud，8N1
- 最终不使用 WM8978

接线、协议和复现实验细节见 `docs` 与 `interaction/docs`。

