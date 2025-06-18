# Use uma imagem base oficial do Nginx (baseada em Debian)
FROM nginx:latest
# Ou uma versão específica, ex: nginx:1.27-bookworm

# Instale o pacote nginx-extras (que inclui o módulo geoip2) e libmaxminddb0
# nginx-extras geralmente já tem o módulo GeoIP2 compilado.
# libmaxminddb0 é a biblioteca para ler os arquivos .mmdb.
RUN apt-get update && \
    apt-get install -y nginx-extras libmaxminddb0 --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

# Crie o diretório para os bancos de dados GeoIP
RUN mkdir -p /usr/share/GeoIP/

# Copie os bancos de dados GeoIP que você baixou para dentro da imagem
# Certifique-se que os arquivos GeoLite2-City.mmdb e GeoLite2-Country.mmdb
# estão no diretório 'geoip_databases' ao lado do seu Dockerfile.
COPY ./geoip_databases/GeoLite2-Country.mmdb /usr/share/GeoIP/GeoLite2-Country.mmdb
COPY ./geoip_databases/GeoLite2-City.mmdb /usr/share/GeoIP/GeoLite2-City.mmdb

# Copie seu arquivo de configuração principal do Nginx
# Este arquivo deve conter as diretivas geoip2 (veja exemplo abaixo)
COPY nginx.conf /etc/nginx/nginx.conf

# Exponha a porta padrão do Nginx
EXPOSE 80

# Comando padrão para iniciar o Nginx
CMD ["nginx", "-g", "daemon off;"]