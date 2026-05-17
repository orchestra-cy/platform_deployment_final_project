FROM php:8.3-fpm as builder

WORKDIR /app

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN apt-get update && apt-get install -y \
    git \
    unzip \
    curl \
    nodejs \
    npm \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

ENV COMPOSER_ALLOW_SUPERUSER=1

COPY composer.json composer.lock ./

RUN composer install --no-interaction --no-scripts --optimize-autoloader --no-dev

COPY . .


# Now run post-install scripts after app code is available
RUN composer install --no-interaction --optimize-autoloader --no-dev --no-ansi || true
RUN php bin/console importmap:install --no-interaction

RUN php bin/console cache:warmup --env=prod --no-debug || true

FROM php:8.3-fpm as runtime

WORKDIR /app

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    && docker-php-ext-install pdo pdo_mysql \
    && rm -rf /var/lib/apt/lists/*

RUN { \
    echo ""; \
    echo "; App env"; \
    echo "clear_env = no"; \
    echo "env[APP_ENV] = prod"; \
    echo "env[APP_DEBUG] = 0"; \
} >> /usr/local/etc/php-fpm.d/www.conf

COPY --from=builder /app /app

RUN mkdir -p /app/var && \
    chown -R www-data:www-data /app && \
    chmod -R 755 /app && \
    chmod -R 775 /app/var

COPY nginx-main.conf /etc/nginx/nginx.conf

RUN rm -rf /etc/nginx/conf.d/* /etc/nginx/sites-enabled /etc/nginx/sites-available
COPY nginx.conf /etc/nginx/conf.d/symfony.conf

COPY entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
