https://stackoverflow.com/a/75915264/227926

**Laravel 11** required PHP extensions (completed)

- `php`: PHP (Hypertext Preprocessor) language interpreter.
- `php-fpm`: PHP FastCGI Process Manager.
- `php-cli`: Command-line interface for PHP.
- `php-common`: Common files for PHP.
- `php-mysql`: MySQL database integration for PHP.
- `php-zip`: ZIP archive support for PHP.
- `php-gd`: GD extension for PHP (image processing).
- `php-mbstring`: Multibyte string support for PHP.
- `php-curl`: cURL extension for PHP (URL transfers).
- `php-xml`: XML support for PHP.
- `php-bcmath`: Arbitrary precision mathematics extension for PHP.
- `openssl`: OpenSSL toolkit (used by PHP for encryption).
- `php-json`: JSON support for PHP.
- `php-tokenizer`: Tokenizer support for PHP (used for parsing PHP code).

These extensions will cover 99% of common php usage.

update and upgrade:

```
sudo apt update && sudo apt upgrade -y
```

add repository:

```
sudo add-apt-repository ppa:ondrej/php
```

update repository:

```
sudo apt update
```

## Newest version of php:

The complete list of all the needed PHP extensions:

```
sudo apt-get install -y php php-cli php-common php-fpm php-mysql php-zip php-gd php-mbstring php-curl php-xml php-bcmath openssl php-json php-tokenizer
```

#### If you want php extension for the specific version of PHP:

The complete list of all the needed PHP extensions with version 8.3 for Laravel 11:

```
sudo apt-get install -y php8.3 php8.3-cli php8.3-common php8.3-fpm php8.3-mysql php8.3-zip php8.3-gd php8.3-mbstring php8.3-curl php8.3-xml php8.3-bcmath openssl php8.3-json php8.3-tokenizer
```

you can replace `8.3` with the version that you want.

#### Different versions of PHP for different versions of Laravel:

if you want to have different version of Laravel, you need different version of PHP, and you can have it with `php-fpm`

#### Run queue jobs or cronjobs:

For running queue jobs automatically, you need to have `php-cli` and run it with cronjob or supervisor

For CentOS 7 or RHEL 7 use `yum`

For CentOS 8 or RHEL 8 use `dnf`

For Arch Linux use `pacman`

For OpenSUSE use `zypper`
