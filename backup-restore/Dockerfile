FROM php:8.2-apache

# Instalar dependências do sistema
RUN apt-get update && \
    apt-get install -y \
        unzip \
        git \
        postgresql-client \
        gzip \
        libpq-dev \
        build-essential \
        pkg-config && \
    docker-php-ext-install zip pdo pdo_pgsql && \
    rm -rf /var/lib/apt/lists/*

# Instalar Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Instalar Twig
RUN composer require twig/twig

# Configurar diretório de trabalho
WORKDIR /var/www/html

# Copiar aplicação
COPY ./public /var/www/html
COPY ./scripts /scripts
COPY ./templates /var/www/html/templates

# Dar permissões para o usuário www-data
RUN chown -R www-data:www-data /var/www/html
RUN chmod +x /scripts/*.sh

# Configurar Apache para usar .htaccess
RUN sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
RUN a2enmod rewrite