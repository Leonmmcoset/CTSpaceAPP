# 接口适配记录

依据为用户提供的 [API 文档](API.md)，并对照 `https://forum.ctspace.xyz/api/docs-json`、官网当前客户端和公开 GET 响应。2026-11-01 的 Swagger 共列出 253 个路径、307 个操作，但大部分请求 DTO 没有属性定义，因此不直接从空 DTO 生成写请求。

## 已处理的差异

| 项目 | 当前适配 |
| --- | --- |
| API 根路径 | 默认 `https://forum.ctspace.xyz/api`；相对资源地址相对站点根目录解析 |
| 验证码 | `{token,image,pow:{challenge,difficulty}}`；SHA-256 输入为 `challenge:nonce`，哈希十六进制前 difficulty 位为 0 |
| 登录 | 兼容 `{token,user}`；返回 `needSecurityAnswer` 时使用 `/auth/login/security`，完成前不保存会话 |
| 注册 | 官网当前基本请求为 `{username,email,password}`；邮件激活另行完成 |
| 重发邮件 | 文档使用 `identifier`，官网使用 `email`；当前保留文档的 identifier 请求 |
| 改用户名 | 文档/Swagger 为 POST，官网代码为 PATCH；当前按文档使用 POST |
| 搜索 | 分类名为 `discussions/posts/projects/extensions/users`；响应按类分组，各组含 items/total；全部结果按最大组页数继续分页 |
| 收藏/关注话题 | POST 为切换状态，非每次创建新记录；另有 check 查询 |
| 表态 | summary 参数为 targetType 和逗号分隔的 ids，响应 map 按目标 ID 索引 |
| 回复 | 支持 replyToId；附件通过 PATCH resources 关联 discussionId/postId |
| 上传 | multipart 中另传 name 保存中文文件名；不自动重试写请求 |
| 作品版本 | 使用 newFileResourceId/versionLabel/changelog；allowDownload=false 时不暴露任意版本下载入口 |
| 作品网址 | 官网作品页是 `/works/:id`，短链为 `/g/:slug`；编辑器模板对绝对 sb3 URL 编码后替换 `{url}` |
| 云盘分享 | 当前官网分享页为 `/c/:shareId`，同时识别旧 `/d/:shareId` 链接；文件直链为 `/api/drive/raw/:shareId` |
| 云变量 | 项目键为 projectId；变量为 `{variables:{name:value}}`，历史为 `{history:[...]}`；开发 API 使用 x-cloud-token |
| 现金金额 | 商城和财务金额按分转元显示；下单原样提交 productId/quantity/payMethod/addressId/variantSku |
| 支付结果 | 处理 jump、qrcode、html，不在超时后自动重建订单 |
| IM | Socket.IO path `/api/im/ws`，auth 为 `{token}`；消息按 ID 合并并按创建时间排序 |
| IM 转发 | items 为 `[{kind,id}]`，目标为 targetThreadId/targetGroupId；mode 为 single |
| 群已读 | 官网调用 `/im/groups/:id/read`，Swagger 索引未列出；客户端容忍该辅助请求失败 |
| 积分红包 | 群红包使用 random/equal；总积分、份数在提交前校验并确认 |
| 直播 | Socket.IO path `/api/live/ws`，query 中传 sessionId；REST 响应分别取 messages/questions/lotteries |
| OrigMark | verify 响应含 verified/signature/publicKey；客户端显示服务器验证结果，未声称本地离线验证 |

## 请求与存储

Bearer 仅发送到所配置 API 的同源 `/api/` 子路径。第三方图片、下载地址和网页不注入令牌。站外链接限制为 HTTP、HTTPS 或 mailto，源码不执行。

GET 仅在未收到服务端响应的网络故障中重试一次；写请求均不自动重试。发布后附件关联失败会保留已发布 ID，后续只继续关联。超时错误提示先检查结果，避免用户误以为写入必然失败。

令牌由系统安全存储保存。退出时写入非敏感的注销标记，即使系统密钥环暂时不可访问，重新启动也不会重新使用已注销会话。草稿按账号和内容目标分离；写入串行排队，快照在排队前固定，发布删除同样遵循队列顺序。

## 尚待确认

- OrigMark 登记字段没有公开完整契约，独立站点本次返回 521，因此新登记保留官网入口；不构造未知字段，不伪造 Origin/Referer 绕过预览权限。原文件下载由服务端权限判断，若部署要求另发审批 token，需要进一步补齐令牌领取契约。
- 直播当前返回 `{session:null}`，真实场次的播放、实时事件及抽奖状态需要有场次时联调。官网播放有自定义 HLS playlist loader，当前使用官网播放器。
- API Key 权限变更保留官网入口。素材/小游戏和部分用户操作缺少可公开读取的写响应示例，按已核实的官网参数实现，需要在测试账号和测试服务上继续验收。
- 管理接口、客服工作台、真实支付、生产发帖和私信未作为自动化测试目标。

若服务端更新契约，应先更新此表，再更新相应模块和必要的行为测试。
