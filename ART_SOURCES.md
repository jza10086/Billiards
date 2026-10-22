# 美术、音效与字体来源

本项目使用原创程序化 3D 球桌与球体，配合下列免费第三方材质、音效和字体。未使用商业桌球游戏的模型、截图、商标或球台品牌。

来源与许可核验日期：2026-10-22。

## Poly Haven：Wood Table 001

- 作者：Dimitrios Savva（摄影）、Rico Cilliers（处理）。
- 官方素材页：https://polyhaven.com/a/wood_table_001
- 官方许可说明：https://polyhaven.com/license
- 许可：CC0 1.0 Universal。可修改、商用，并可将原始素材随项目源码重新分发，不要求署名；本项目仍保留来源记录。
- 本地目录：`assets/textures/wood_table_001/`。
- 使用文件：`wood_table_001_diff_1k.jpg`、`wood_table_001_nor_gl_1k.jpg`、`wood_table_001_rough_1k.jpg`。
- 用途：球桌与环境中的木质表面；OpenGL 法线纹理与粗糙度纹理。素材未重新压缩；游戏可调整材质色调、UV 与强度。
- 原始下载路径：`https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/wood_table_001/`，后接上述文件名。
- 完整 CC0 文本：`assets/textures/wood_table_001/LICENSE_CC0.txt`，从系统标准 CC0 1.0 法律文本副本保留；官方文本链接 https://creativecommons.org/publicdomain/zero/1.0/legalcode 。

## Kenney：Impact Sounds 1.0

- 作者：Kenney。
- 官方素材页：https://kenney.nl/assets/impact-sounds
- 官方通用说明：https://kenney.nl/support
- 许可：CC0。官方包内许可明确允许个人、教育与商业用途。
- 本地文件：`assets/audio/impactWood_light_001.ogg`、`assets/audio/impactSoft_medium_000.ogg`。
- 用途：短促击球/碰撞反馈与落袋软撞声。音频并非专门实录的专业桌球声，属于适配的轻量撞击音效；播放时可调节音量与音高。
- 原始音频未修改、转码。原包 130 个音频中仅收录这两个使用文件，未收录宣传图或品牌标识。
- 原包许可原文：`assets/audio/KENNEY_LICENSE.txt`。
- 官方下载：https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip

## Noto Sans CJK SC 字体

- 项目：Noto CJK，https://github.com/notofonts/noto-cjk 。
- 文件：`assets/fonts/NotoSansSC-Regular.otf`。
- 许可：SIL Open Font License 1.1；完整原文见 `assets/fonts/LICENSE.txt`。
- 从既有合法字体资源集中复用，供离线中文 UI 渲染。字体不以独立收费商品形式出售。
- 该字体许可与 CC0 素材许可不同，不应将字体改标为 CC0。

## 本项目原创内容

- 球桌结构、库边、六个袋口、球杆、灯具及环境几何由项目代码创建，不依赖下载的球桌模型。
- 实色球/花色球的编号、色带与基础材质为程序化生成。
- 台呢、黄铜和其他未列出的基础材质由项目生成；布局、UI 和反馈动画为本项目实现。

## 调研但未收录

曾核验 ambientCG Wood049 与 Fabric061 的 CC0 页面，但其下载服务器返回 HTTP 403，未将这些资产包含在项目中，也不将它们列为实际采用素材。

### 球号位图的字形来源

`assets/balls/ball_00.png` 至 `ball_15.png` 为本项目生成的球面贴图；数字字形使用系统 DejaVu Sans Bold 渲染，非从现有桌球游戏截图裁切。DejaVu 字体项目：https://dejavu-fonts.github.io/ 。项目未捆绑该字体二进制，渲染后的球号图像可独立使用；许可参考 https://dejavu-fonts.github.io/License.html 。
