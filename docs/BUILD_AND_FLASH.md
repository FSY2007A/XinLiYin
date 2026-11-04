# 构建与烧录

## 软件环境

- Gowin EDA V1.9.12.03；
- 器件：GW5AT-60B；
- 封装/器件型号：GW5AT-LV60PG484AC1/I0，device version B；
- 顶层：`top_matrix_j13_pcm_screen`。

## 从源码重新构建

```powershell
cd .\build
.\rebuild.ps1
```

或：

```powershell
cd .\build
& "C:\Gowin\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe" "build.tcl"
```

输出位于：

```text
build/_work/xinliyin_j13_submission/impl/pnr/xinliyin_j13_submission.fs
```

构建脚本在 `build/_work/src` 中创建扁平暂存源码目录。直接保留分类 RTL 的原因是可读性；暂存目录用于满足 Gowin 对 include 文件和 `$readmemh` 的源文件同级查找规则。

## SRAM 临时测试

```powershell
& "C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe" `
  --device "GW5AT-60B" `
  --operation_index 2 `
  --fsFile ".\firmware\reference\J13_Piano_Realistic_Erhu_Guzheng_Organ_NoWM.fs" `
  --cable "USB Debugger A"
```

## 外部 Flash 持久烧录

```powershell
& "C:\Gowin\Gowin_V1.9.12.03_x64\Programmer\bin\programmer_cli.exe" `
  --device "GW5AT-60B" `
  --operation_index 54 `
  --fsFile ".\firmware\reference\J13_Piano_Realistic_Erhu_Guzheng_Organ_NoWM.fs" `
  --cable "USB Debugger A"
```

成功标志：

```text
Program and Verify Flash successfully.
```

烧录期间不得断电或拔出下载器。

## 串口屏界面工程

最终界面工程位于：

```text
interaction/ui/final/ture1.HMI
```

该文件需使用对应的 TJC 串口屏编辑工具打开并单独下载到屏幕。`.HMI` 工程不会由 Gowin 位流自动嵌入；界面资源下载和 FPGA 位流烧录是两个独立步骤。

