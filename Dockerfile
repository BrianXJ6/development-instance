FROM php:8.5-fpm-alpine

WORKDIR /var/www

ARG NODE_VERSION=24

ENV WWWUSER=1000
ENV WWWGROUP=1000
ENV TZ=America/Recife
ENV DEBIAN_FRONTEND=noninteractive

# Installing essential packages
RUN apk update && apk upgrade && apk add zlib libpng libzip imagemagick ffmpeg sqlite \
    librsvg libwebp libxpm libjpeg-turbo tzdata nginx supervisor vim nano nodejs npm zip unzip \
    su-exec curl ca-certificates git bash shadow libcap mysql-client mariadb-client mariadb-connector-c

# Configuring GIT for path safe
RUN git config --global --add safe.directory /var/www

# Configuring Timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime

# Installation of tools and temporary packages just for build
RUN apk add --virtual .temp-deps $PHPIZE_DEPS zlib-dev libpng-dev libzip-dev mariadb-connector-c-dev \
    imagemagick-dev ffmpeg-dev librsvg-dev libwebp-dev libxpm-dev libjpeg-turbo-dev

# Installing and enabling PHP extensions
RUN pecl install redis pcov xdebug imagick && \
    docker-php-ext-configure gd --with-jpeg --with-webp --with-xpm && \
    docker-php-ext-install gd zip pdo_mysql pcntl && \
    docker-php-ext-enable redis pcov imagick

# Copying and using php.ini optimized for development
RUN cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# Installing Composer
RUN curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer

# Fine adjustments for proper functioning in a development environment
RUN mkdir -p /var/log/supervisor && mkdir -p /.composer && \
    setcap "cap_net_bind_service=+ep" /usr/local/bin/php && \
    groupadd --force -g $WWWGROUP sail && \
    useradd -ms /bin/sh --no-user-group -g $WWWGROUP -u $WWWUSER sail && \
    usermod -aG www-data sail && usermod -aG sail www-data && \
    chmod -R ugo+rw /.composer && chmod -R ugo+rw /var/www

# Section for copying extra configuration files and directories
COPY nginx.conf /etc/nginx/nginx.conf
COPY start-container /usr/local/bin/start-container
COPY php.ini /usr/local/etc/php/conf.d/99-php.ini
COPY xdebug.ini /usr/local/etc/php/conf.d/99-xdebug.ini
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /usr/local/bin/start-container

# Cleaning up the image
RUN apk del .temp-deps

EXPOSE 80

ENTRYPOINT ["start-container"]
