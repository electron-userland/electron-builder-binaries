FROM buildpack-deps:bionic-curl

RUN apt-get -qq update && apt-get -qq upgrade && apt-get install -qq libssl-dev libcurl4-openssl-dev libgsf-1-dev autoconf build-essential unzip libtool

RUN curl -L https://github.com/mtrojnar/osslsigncode/archive/master.zip -o f.zip && unzip f.zip && \
  cd osslsigncode-master && ./autogen.sh && ./configure CFLAGS='-g -O3' GSF_LIBS='-l:libgsf-1.a -lgobject-2.0 -lglib-2.0 -lxml2 -l:libz.a -l:libbz2.a' && make install

CMD cp /usr/local/bin/osslsigncode /files
