# 音频与第三方素材来源

## 当前参与最终固件的素材

### 二胡

- 仓库：`sfzinstruments/aliexpress-erhu`
- 地址：https://github.com/sfzinstruments/aliexpress-erhu
- 许可：CC0-1.0
- 使用：C4、E4、G4、A4 对应的持续音 WAV，处理后生成四个 ADPCM bank。

### 古筝

- 仓库：`sparklecatta-lang/XSXB-Band-Samples`
- 地址：https://github.com/sparklecatta-lang/XSXB-Band-Samples
- 许可：CC0-1.0
- 使用：C4、G4、D5、G5 对应的古筝 FLAC，处理后生成四个 ADPCM bank。

### 管风琴

- 素材：Pitea MHS sampleset；
- 记录/贡献者：Lars Palo、Graham Goode、Panos Ghekas；
- 来源：https://familjenpalo.se/vpo/pitea-mhs/
- 原始录音许可：CC BY-SA 2.5；
- 项目处理：六音栓组合、单声道重采样、attack/sustain loop、IMA ADPCM；
- 派生采样数据继续遵循 CC BY-SA 2.5。

## 仅作兼容/历史参考的素材

- 钢弦木吉他：Discord SFZ General MIDI Bank，CC0；
- STK 派生系数：仅用于未参与最终固件的 `reference/rtl/bowed_wave.v`，STK 许可位于 `THIRD_PARTY_LICENSES/STK_LICENSE.txt`；
- 历史弦乐 wavetable：许可见 `STRING_SAMPLE_LICENSE.txt`。

## 注意

音频素材许可不会自动覆盖团队原创的 Verilog、界面和文档。若对外发布，请根据比赛/学校要求补充作者、单位和作品级代码许可。详见 `docs/LICENSE_STATUS.md`。

