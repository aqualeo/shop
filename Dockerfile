# Production image for Railway (and any Docker host). Not used by docker-compose.yml, which relies on .docker/Dockerfile.
ARG PHP_VERSION="8.3-apache"
ARG NODE_VERSION="20.19.5"

FROM prestashop/base:${PHP_VERSION} AS php-deps
WORKDIR /var/www/html
# Without this Composer disables plugins as root, so composer/installers never places themes and modules.
ENV COMPOSER_ALLOW_SUPERUSER=1
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer
COPY . .
RUN COMPOSER_PROCESS_TIMEOUT=600 composer install --no-dev --optimize-autoloader --prefer-dist --no-interaction --no-progress \
  && test -d themes/hummingbird && test -d themes/classic/_dev

FROM node:${NODE_VERSION}-bookworm AS assets
WORKDIR /var/www/html
COPY --from=php-deps /var/www/html .
RUN ./tools/assets/build.sh all --force \
  && find . -name node_modules -type d -prune -exec rm -rf {} + \
  && find . -name buildLock -delete

FROM prestashop/base:${PHP_VERSION}
WORKDIR /var/www/html
COPY --from=assets --chown=www-data:www-data /var/www/html .
COPY --chmod=755 .railway/entrypoint.sh /usr/local/bin/railway-entrypoint
COPY .railway/apache-proxy.conf /etc/apache2/conf-available/railway-proxy.conf
# mod_php needs prefork; the image can end up with another MPM enabled as well ("More than one MPM loaded").
RUN a2dismod -f mpm_event mpm_worker || true \
  && a2enmod mpm_prefork \
  && a2enconf railway-proxy \
  && sed -i "s/define('_PS_MODE_DEV_', true);/define('_PS_MODE_DEV_', false);/" config/defines.inc.php

CMD ["railway-entrypoint"]
