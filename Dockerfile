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

RUN mkdir -p /etc/openelis-global/ /etc/ssl/private/ /etc/ssl/certs/

# --- Step 1: Generate internal CA keypair (root of trust) ---
RUN openssl genrsa -out /etc/ssl/private/ca.key 4096

RUN openssl req -x509 -new -nodes \
    -key /etc/ssl/private/ca.key \
    -sha256 -days 1826 \
    -out /etc/ssl/certs/ca.crt \
    -subj "/C=US/ST=WA/L=Seattle/O=I-TECH-UW/OU=DIGI/CN=OpenELIS-Internal-CA"

# --- Step 2: Generate backend server keypair and sign with the CA ---
RUN openssl genrsa -out /etc/ssl/private/server.key 2048

RUN openssl req -new \
    -key /etc/ssl/private/server.key \
    -out /tmp/server.csr \
    -subj "/C=US/ST=WA/L=Seattle/O=I-TECH-UW/OU=DIGI/CN=oe.openelis.org"

RUN openssl x509 -req \
    -in /tmp/server.csr \
    -CA /etc/ssl/certs/ca.crt \
    -CAkey /etc/ssl/private/ca.key \
    -CAcreateserial \
    -out /etc/ssl/certs/server.crt \
    -days 365 \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:oe.openelis.org,DNS:*.openelis.org,DNS:*.openelis-global.org")

# --- Step 3: Generate client-facing keypair and sign with the CA ---
RUN openssl genrsa -out /etc/ssl/private/client-facing.key 2048

RUN openssl req -new \
    -key /etc/ssl/private/client-facing.key \
    -out /tmp/client-facing.csr \
    -subj "/C=US/ST=WA/L=Seattle/O=I-TECH-UW/OU=DIGI/CN=localhost"

RUN openssl x509 -req \
    -in /tmp/client-facing.csr \
    -CA /etc/ssl/certs/ca.crt \
    -CAkey /etc/ssl/private/ca.key \
    -CAcreateserial \
    -out /etc/ssl/certs/client-facing.crt \
    -days 365 \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:localhost,DNS:*.openelis.org,DNS:*.openelis-global.org")

# --- Step 4: Copy CA cert as apache-selfsigned.crt for nginx client-facing TLS (backward compat) ---
RUN cp /etc/ssl/certs/client-facing.crt /etc/ssl/certs/apache-selfsigned.crt && \
    cp /etc/ssl/private/client-facing.key /etc/ssl/private/apache-selfsigned.key

# --- Step 5: Pack backend server cert into keystore (Tomcat port 8443) ---
RUN openssl pkcs12 \
    -inkey /etc/ssl/private/server.key \
    -in /etc/ssl/certs/server.crt \
    -export \
    -out /etc/openelis-global/keystore \
    --passin pass:${KEYSTORE_PW} \
    --passout pass:${KEYSTORE_PW}

# --- Step 6: Client-facing keystore ---
RUN openssl pkcs12 \
    -inkey /etc/ssl/private/client-facing.key \
    -in /etc/ssl/certs/client-facing.crt \
    -export \
    -out /etc/openelis-global/client_facing_keystore \
    --passin pass:${KEYSTORE_PW} \
    --passout pass:${KEYSTORE_PW}

# --- Step 7: Truststore — import CA cert so services trust the internal CA chain ---
RUN keytool -import -alias internalCA \
    -file /etc/ssl/certs/ca.crt \
    -storetype pkcs12 \
    -keystore /etc/openelis-global/truststore \
    -storepass ${TRUSTSTORE_PW} \
    -noprompt

# --- Step 8: Export CA cert to certs volume so nginx can trust the backend ---
RUN cp /etc/ssl/certs/ca.crt /etc/ssl/certs/ca.crt

RUN chmod -R a+rwx /etc/openelis-global/
