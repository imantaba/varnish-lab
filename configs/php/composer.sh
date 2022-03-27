#!/bin/sh

EXPECTED_SIGNATURE=$(php -r "readfile('https://composer.github.io/installer.sig');")
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
ACTUAL_SIGNATURE=$(php -r "echo hash_file('SHA384', 'composer-setup.php');")

if [ "$EXPECTED_SIGNATURE" = "$ACTUAL_SIGNATURE" ]
then
    php composer-setup.php --quiet --install-dir=/scripts --filename=composer
    RESULT=$?
    mv /scripts/composer /usr/local/bin/composer
    chmod +x /usr/local/bin/composer

    rm composer-setup.php
    exit $RESULT
else
    >&2 echo 'ERROR: Invalid installer signature'
    rm composer-setup.php
    exit 1
fi
