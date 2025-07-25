##
# Build Stage
#
FROM ubuntu:focal as build

ENV KEYSTORE_PW="kspass"
ENV TRUSTSTORE_PW="tspass"

##
# Prerequesites
#
RUN apt-get update && apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      openssl net-tools python default-jdk maven \ 
      apache2-utils git apt-transport-https \
      ca-certificates curl gnupg lsb-release software-properties-common\
    && apt-get clean

##
# Certificates
#

# Self-signed Certs
RUN openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache-selfsigned.key -out /etc/ssl/certs/apache-selfsigned.crt \ 
    -subj "/C=US/ST=WA/L=Seattle/O=I-TECH-UW/OU=DIGI/CN=localhost" \
    -addext "subjectAltName=DNS:*.openelis.org,DNS:*.openelis-global.org"

RUN mkdir /etc/openelis-global/
# Keystore
RUN openssl pkcs12 -inkey /etc/ssl/private/apache-selfsigned.key -in /etc/ssl/certs/apache-selfsigned.crt -export -out /etc/openelis-global/keystore --passin pass:${KEYSTORE_PW} --passout pass:${KEYSTORE_PW}
# # Client-facing Keystore
RUN cp /etc/openelis-global/keystore /etc/openelis-global/client_facing_keystore
# # Truststore
RUN keytool -import -alias oeCert -file /etc/ssl/certs/apache-selfsigned.crt -storetype pkcs12 -keystore /etc/openelis-global/truststore -storepass ${TRUSTSTORE_PW} -noprompt

RUN chmod -R a+rwx /etc/openelis-global/
