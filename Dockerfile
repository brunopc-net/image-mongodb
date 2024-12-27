# Base taken from https://github.com/docker-library/mongo/blob/master/8.0/Dockerfile
FROM ubuntu:noble-20241118.1

ARG MONGO_VERSION=8.0.4 \
	MONGO_MAJOR="${MONGO_VERSION%.*}" \
	MONGO_PGPKEY_FINGERPRINT=4B0752C1BCA238C0B4EE14DC41DE058A4E7DCA05 \
	MONGO_PGPKEY_URL=https://pgp.mongodb.com/server-${MONGO_MAJOR}.asc \
	# Options for MONGO_PACKAGE: mongodb-org OR mongodb-enterprise
	MONGO_PACKAGE=mongodb-org \
	# Options for MONGO_REPO: repo.mongodb.org OR repo.mongodb.com
	MONGO_REPO=repo.mongodb.org \
	\
	GOSU_VERSION=1.17 \
	GOSU_DOWNLOAD_URL=https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64 \
	\
	JSYAML_VERSION=3.13.1 \
	JSYAML_CHECKSUM=662e32319bdd378e91f67578e56a34954b0a2e33aca11d70ab9f4826af24b941 \
	JSYAML_DOWNLOAD_URL=https://registry.npmjs.org/js-yaml/-/js-yaml-${JSYAML_VERSION}.tgz
	
# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN set -eux; \
	groupadd --gid 999 --system mongodb; \
	useradd --uid 999 --system --gid mongodb --home-dir /data/db mongodb; \
	mkdir -p /data/db /data/configdb; \
	chown -R mongodb:mongodb /data/db /data/configdb

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		ca-certificates=20240203 \
		jq=1.7.1-3build1 \
		numactl=2.0.18-1build1 \
	; \
	rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update && apt-get install -y --no-install-recommends \
		gnupg \
		wget \
	; \
	rm -rf /var/lib/apt/lists/*;

# grab gosu for easy step-down from root (https://github.com/tianon/gosu/releases)
RUN set -eux; 
RUN wget -O /usr/local/bin/gosu $GOSU_DOWNLOAD_URL; 
RUN wget -O /usr/local/bin/gosu.asc "$GOSU_DOWNLOAD_URL.asc"; 
RUN export GNUPGHOME="$(mktemp -d)"; 
RUN gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; 
RUN gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; 
RUN gpgconf --kill all;

# smoke test
RUN set -eux; \
	chmod +x /usr/local/bin/gosu; \
	gosu --version; \
	gosu nobody true; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc;

# grab "js-yaml" for parsing mongod's YAML config files (https://github.com/nodeca/js-yaml/releases)
RUN set -eux; \
	mkdir -p /opt/js-yaml/; \
	wget -O /opt/js-yaml/js-yaml.tgz ${JSYAML_DOWNLOAD_URL}; \
	echo "$JSYAML_CHECKSUM */opt/js-yaml/js-yaml.tgz" | sha256sum -c -; \
	tar -xz --strip-components=1 -f /opt/js-yaml/js-yaml.tgz -C /opt/js-yaml package/dist/js-yaml.js package/package.json; \
	rm /opt/js-yaml/js-yaml.tgz; \
	ln -s /opt/js-yaml/dist/js-yaml.js /js-yaml.js;

RUN set -eux; \
# download/install MongoDB PGP keys
	export GNUPGHOME="$(mktemp -d)"; \
	wget -O KEYS ${MONGO_PGPKEY_URL}; \
	gpg --batch --import KEYS; \
	mkdir -p /etc/apt/keyrings; \
	gpg --batch --export --armor ${MONGO_PGPKEY_FINGERPRINT} > /etc/apt/keyrings/mongodb.asc; \
	gpgconf --kill all; \
	rm -rf "$GNUPGHOME" KEYS;

RUN set -eux; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	\
# smoke test
	echo "WWWWWWWWWWWWWWWWWWWWWWWW ${savedAptMark} WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"; \
	dpkg-query -Wf '${Installed-Size}\t${Package}\n' | sort -n;

RUN mkdir /docker-entrypoint-initdb.d

RUN set -x \
# installing "mongodb-enterprise" pulls in "tzdata" which prompts for input
	&& echo "deb [ signed-by=/etc/apt/keyrings/mongodb.asc ] http://$MONGO_REPO/apt/ubuntu noble/${MONGO_PACKAGE%-unstable}/$MONGO_MAJOR multiverse" \
	   | tee "/etc/apt/sources.list.d/${MONGO_PACKAGE%-unstable}.list" \
	&& export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update && apt-get install -y \
		${MONGO_PACKAGE}=$MONGO_VERSION \
		${MONGO_PACKAGE}-server=$MONGO_VERSION \
		${MONGO_PACKAGE}-shell=$MONGO_VERSION \
		${MONGO_PACKAGE}-mongos=$MONGO_VERSION \
		${MONGO_PACKAGE}-tools=$MONGO_VERSION \
		${MONGO_PACKAGE}-database=$MONGO_VERSION \
		${MONGO_PACKAGE}-database-tools-extra=$MONGO_VERSION \
	&& rm -rf /var/lib/apt/lists/* \
	&& rm -rf /var/lib/mongodb \
	&& mv /etc/mongod.conf /etc/mongod.conf.orig

VOLUME /data/db /data/configdb

# ensure that if running as custom user that "mongosh" has a valid "HOME"
# https://github.com/docker-library/mongo/issues/524
ENV HOME=/data/db

COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

EXPOSE 27017
CMD ["mongod"]