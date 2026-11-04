# 乐器采样生成与校验

## 文件

- `build_realistic_banks.py`：从二胡 wave 和古筝 FLAC 生成 13 kHz 单声道 IMA ADPCM bank；
- `verify_generated_banks.py`：解码生成的 `.mem`，检查峰值、RMS、循环接缝并生成 WAV 预览；
- `manifest.json`：每个 bank 的根音、循环参数、源文件和处理结果；
- `verification.json`：ADPCM 解码校验结果；
- `previews/`：8 个 bank 的离线预览 WAV。

## 依赖

- Python 3.8+；
- 外部 `ffmpeg` 可执行文件；
- 脚本中的源路径和 ffmpeg 路径应按本机环境修改。

## 重新生成

```powershell
python .\build_realistic_banks.py
python .\verify_generated_banks.py
```

生成前需重新下载或准备：

- `sfzinstruments/aliexpress-erhu` 的持续音 WAV；
- `sparklecatta-lang/XSXB-Band-Samples` 的古筝 FLAC。

两个仓库均声明 CC0-1.0。处理后的 `sample_adpcm_*.mem` 已放在 `data/instrument_samples`。

