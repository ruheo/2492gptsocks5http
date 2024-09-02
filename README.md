# GPT新改一键全自动Socks5+http脚本
适用于 Debian 9+、Ubuntu 20.04+ 和 CentOS 7+ 

默认端口，用户名、密码
```bash
bash <(wget -qO- https://raw.githubusercontent.com/ruheo/2492gptsocks5http/main/socks5.sh)
```

默认端口，无认证
```bash
curl -fsSL https://raw.githubusercontent.com/ruheo/2492gptsocks5http/main/socks5.sh | sudo bash -s -- noauth
```

自定义端口，无认证
```bash
bash <(curl -sL https://raw.githubusercontent.com/ruheo/2492gptsocks5http/main/socks5.sh) noauth 端口
```

自定义端口，用户名、密码
```bash
bash <(wget -qO- https://raw.githubusercontent.com/ruheo/2492gptsocks5http/main/socks5.sh) password 端口 用户名 密码
```
