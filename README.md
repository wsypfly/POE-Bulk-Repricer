# POE Bulk Repricer

流放之路（Path of Exile）批量标价工具，支持自动识别仓库页物品并批量修改定价。

## 功能

- 自动识别仓库页中高亮的物品
- 批量修改物品定价（打折、统一加减价）
- 检测预览（F4）和批量改价（F3）两种模式
- 支持四舍五入、向下取整、向上取整
- 可自定义边框颜色和热键

## 安装

### 方式一：源码运行

1. 安装 [AutoHotkey v1](https://www.autohotkey.com/)
2. 安装 Python 依赖：
   ```
   pip install -r "POE最终标价工具/requirements.txt"
   ```
3. 双击 `POE最终标价工具/POE标价工具.ahk`

### 方式二：打包版

从 [Releases](https://github.com/wsypfly/POE-Bulk-Repricer/releases) 下载，解压后直接运行。

## 使用步骤

1. 打开流放之路，进入要改价的仓库页
2. 先用 **F4**（检测预览）确认能识别到物品
3. 设置改价规则后，使用 **F3**（批量改价）

## 改价规则

| 模式 | 示例 | 说明 |
|------|------|------|
| 打折 | `8` | 原价 x 0.8 |
| 打折 | `8.5` | 原价 x 0.85 |
| 统一减价 | `-5` | 原价 - 5 |
| 统一加价 | `+5` 或 `5` | 原价 + 5 |

最终价格小于 1 时自动按 1 标价。

## 项目结构

```
POE最终标价工具/
  POE标价工具.ahk        # 主脚本（AutoHotkey）
  market_detect_items.py  # 物品检测模块（Python）
  settings.ini            # 配置文件
  build_release.ps1       # 打包脚本
  requirements.txt        # Python 依赖
```

## 配置

编辑 `settings.ini` 可修改：

- 边框检测颜色和容差
- 改价模式和参数
- 热键绑定

## 调试

在界面勾选「调试模式」并保存，运行后会生成：

- `market_detect_items.tsv` — 检测到的物品列表
- `market_discount_debug.txt` — 检测日志
- `market_discount_capture.png` — 检测截图
- `market_discount_log_*.csv` — 改价日志
