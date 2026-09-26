# Yanami

一个用 Flutter 写的个人追番记录 App。

## 功能

- 番剧 / 小说 / 漫画分类 手动 记录
- 观看进度追踪（集数 + 时分秒）
- 小说 / 漫画分册管理（支持自定义卷名、单独封面）
- 多段观看时间记录
- 每日观看热力图
- Bangumi 搜索导入番剧信息（封面、评分、简介）
- 首页当季新番列表
- 本地持久化存储

## 技术栈

- Flutter 3.x
- shared_preferences（本地存储）
- http（网络请求）
- image_picker（相册选图）

## 数据来源

- 新番列表：[ACGNTaiwan/Anime-List](https://github.com/ACGNTaiwan/Anime-List)
- 番剧搜索 / 封面 / 评分：[Bangumi 番组计划](https://bgm.tv)（通过第三方反代访问）

## 说明

- 本项目为个人学习练习作品，代码在 AI 辅助下完成，本人负责需求设计、调试与测试。
- 仅供学习交流使用，不用于任何商业用途。
- 所有番剧数据、封面、评分的版权归原作者所有。

## 构建

```bash
flutter pub get
flutter run