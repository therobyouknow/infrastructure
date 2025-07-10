
# Install Docker CE within Ubuntu running on WSL2

https://docs.docker.com/engine/install/ubuntu/

(see removing previous as well)

```
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
```

```
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

## running composer on local machine

sudo apt-get install php-xml

sudo apt-get install php-gd

sudo apt-get install zip unzip php-zip






## Troubleshooting

For:

```
WSL2-Debian starts docker (failed to start daemon: Error initializing network controller: error obtaining)
```

This worked

https://blog.csdn.net/qq_37196265/article/details/124650639

(had to Google translate and then inspect the code to be able to copy them)

The key things were:

1. First, replace iptables with iptables-legacy:

sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf`

```
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
```

and

2. Enable the packet forwarding function of ipv4:

```
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf`

```

3. Exit and restart Ubuntu 
(close all WSL2 windows and re-open )

The above fix seems to make sense, given that on
it says:

> Docker is only compatible with `iptables-nft` and `iptables-legacy`. Firewall rules 
> created with `nft` are not supported on a system with Docker installed. Make sure
> that any firewall rulesets you use are created with `iptables` or `ip6tables`, and
> that you add them to the `DOCKER-USER` chain, see Packet filtering and firewalls -
> https://docs.docker.com/engine/network/packet-filtering-firewalls/


For ddev not finding docker, do:

```
 sudo groupadd docker
```

```
 sudo usermod -aG docker $USER
```

```
 newgrp docker
```

Verify that you can run docker commands without sudo.

```
 docker run hello-world
```

#### Https not working?

Try these:

https://github.com/ddev/ddev/issues/5026#issuecomment-1609037437

https://stackoverflow.com/questions/65111024/ddev-selectamixmusic.com-starts-up-site-with-http-instead-of-https

### Other research

- https://forums.docker.com/t/cannot-get-docker-desktop-to-run-on-ubuntu-24-04/141004
- https://unix.stackexchange.com/questions/517679/cant-install-docker-containers-on-ubuntu
- https://stackoverflow.com/questions/63497928/ubuntu-wsl-with-docker-could-not-be-found
- https://stackoverflow.com/questions/44678725/cannot-connect-to-the-docker-daemon-at-unix-var-run-docker-sock-is-the-docker
- https://forums.docker.com/t/wsl-cannot-connect-to-the-docker-daemon-at-unix-var-run-docker-sock-is-the-docker-daemon-running/116245/3
- https://techkluster.com/docker/questions-docker/cannot-connect-to-the-docker-daemon-at-unix/
- https://github.com/ddev/ddev/issues/2251
- https://github.com/ddev/ddev/issues/3530
- https://gist.github.com/dennisameling/8317b9dc6b7d971860a4797c64f16eaf




## Other approaches not tried

- https://linuxiac.com/how-to-install-docker-on-ubuntu-24-04-lts/
- https://askubuntu.com/questions/1230189/how-to-install-docker-community-on-ubuntu-20-04-lts
- https://serverfault.com/questions/1110365/when-installing-docker-on-ubuntu-why-isnt-it-as-easy-as-apt-get-install-docker
- https://crapts.org/2022/05/15/install-docker-in-wsl2-with-ubuntu-22-04-lts/


# DDEV Installation

https://ddev.readthedocs.io/en/stable/users/install/ddev-installation/

Once you’ve installed a Docker provider, you’re ready to install DDEV!

## Linux
### Debian/Ubuntu

DDEV's Debian and RPM packages work with apt and yum repositories and most variants that use them, including Windows WSL2:

```
# Add DDEV’s GPG key to your keyring
sudo sh -c 'echo ""'
sudo apt-get update && sudo apt-get install -y curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://pkg.ddev.com/apt/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/ddev.gpg > /dev/null
sudo chmod a+r /etc/apt/keyrings/ddev.gpg

# Add DDEV releases to your package repository
sudo sh -c 'echo ""'
echo "deb [signed-by=/etc/apt/keyrings/ddev.gpg] https://pkg.ddev.com/apt/ * *" | sudo tee /etc/apt/sources.list.d/ddev.list >/dev/null

# Update package information and install DDEV
sudo sh -c 'echo ""'
sudo apt-get update && sudo apt-get install -y ddev

# One-time initialization of mkcert
mkcert -install
(Some versions of Firefox (Developer Edition, Flatpak) may need some extra work with mkcert, see also this issue.)
```
