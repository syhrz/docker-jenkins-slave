FROM nasqueron/php-cli

MAINTAINER Amal Syahreza <amal.syahreza@gmail.com>

# NodeJs Installation and Configuration  #

RUN curl -sL https://deb.nodesource.com/setup_6.x | bash - && \
    apt-get update && \
    apt-get install \ 
    --assume-yes \
    --no-install-recommends \
    nodejs \
    bzip2 \
    unzip \
    xz-utils && \
    rm -rf /var/lib/apt/lists/* && \
    # Install Jshint and less for build dependencies
    npm install \
    -g \
    jshint \
    less &&\
    # This part install and configure java 8 #
    echo 'deb http://httpredir.debian.org/debian jessie-backports main' > /etc/apt/sources.list.d/jessie-backports.list && \
    echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
	echo '#!/bin/sh'; \
	echo 'set -e'; \
	echo; \
	echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
    } > /usr/local/bin/docker-java-home \
    && chmod +x /usr/local/bin/docker-java-home

ENV JAVA_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_VERSION 8u91
ENV JAVA_DEBIAN_VERSION 8u91-b14-1~bpo8+1
# see https://bugs.debian.org/775775
# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
ENV CA_CERTIFICATES_JAVA_VERSION 20140324

RUN set -x && \
    apt-get update && \
    apt-get install -y \
    openjdk-8-jdk="$JAVA_DEBIAN_VERSION" \
    ca-certificates-java="$CA_CERTIFICATES_JAVA_VERSION" && \
    rm -rf /var/lib/apt/lists/* && \
    [ "$JAVA_HOME" = "$(docker-java-home)" ] && \
    # see CA_CERTIFICATES_JAVA_VERSION notes above
    /var/lib/dpkg/info/ca-certificates-java.postinst configure

# Config Arcanist #

RUN apt-get update && \ 
    apt-get install -y \
    mercurial \
    subversion \
    openssh-client \
    locales \
    --no-install-recommends && \
    #rm -r /var/lib/apt/lists/* && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=en_US.UTF-8

RUN cd /opt && \
    git clone https://github.com/phacility/libphutil.git && \
    git clone https://github.com/phacility/arcanist.git && \
    wget https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash

RUN cd $HOME && \
    ln -s /opt/arcanist/bin/arc /usr/local/bin/arc && \
    ln -s /opt/config/gitconfig /root/.gitconfig && \
    ln -s /opt/config/arcrc /root/.arcrc

ENV HOME /home/jenkins

RUN useradd -c "Jenkins user" -d $HOME -m jenkins
RUN curl --create-dirs -sSLo /usr/share/jenkins/slave.jar \
    http://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/2.9/remoting-2.9.jar && \
    chmod 755 /usr/share/jenkins && \
    chmod 644 /usr/share/jenkins/slave.jar

COPY jenkins-slave /usr/local/bin/jenkins-slave
VOLUME ["/opt/config", "/opt/workspace", "/home/jenkins" ]
VOLUME /home/jenkins
WORKDIR /home/jenkins

# Install PostgreSQL #

ENV PG_MAJOR 9.5
ENV PG_VERSION 9.5.3-1.pgdg80+1

RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8 && \
    echo 'deb http://apt.postgresql.org/pub/repos/apt/ jessie-pgdg main' $PG_MAJOR > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y \
    postgresql-common \
    python-software-properties \
    software-properties-common \
    postgresql-9.5 \
    postgresql-client-9.5 \
    postgresql-contrib-9.5 && \
    rm -rf /var/lib/apt/lists/*

USER root

RUN touch /etc/postgresql/9.5/main/pg_hba.conf && \
    echo "host all  all    0.0.0.0/0  trust" >> /etc/postgresql/9.5/main/pg_hba.conf && \
    echo "listen_addresses='*'" >> /etc/postgresql/9.5/main/postgresql.conf && \
    service postgresql restart && \
    mkdir -p /var/run/postgresql && chown -R postgres /var/run/postgresql

VOLUME  ["/etc/postgresql", "/var/log/postgresql", "/var/lib/postgresql"]

EXPOSE 5432

USER postgres

RUN service postgresql start && \
    psql -c "CREATE ROLE root LOGIN INHERIT;" && \
    psql -c "CREATE USER jenkins WITH SUPERUSER PASSWORD 'jenkins';" && \
    createdb -O jenkins jenkins && \
    createdb -O root root && \
    service postgresql stop

USER root

CMD ["/usr/lib/postgresql/9.5/bin/postgres", "-D", "/var/lib/postgresql/9.5/main", "-c", "config_file=/etc/postgresql/9.5/main/postgresql.conf"]
ENTRYPOINT ["jenkins-slave"]
