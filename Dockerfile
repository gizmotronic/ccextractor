FROM alpine:3.5

WORKDIR /build

COPY . .

RUN mkdir -p -m a+rwx /tmp/cc \
 && mkdir -p -m a+rwx ../lib/tessdata \
 && cp linux/build-static.sh /tmp/cc

WORKDIR /tmp/cc

# we want tesseract (for OCR)
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.5/main' >| /etc/apk/repositories
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/v3.5/community' >> /etc/apk/repositories
RUN apk update
RUN apk upgrade

RUN apk add --update bash zsh alpine-sdk perl

# (needed by various static builds below)
# Even though we're going to (re)builid tesseract from source statically, get its dependencies setup by
# installing it now, too.
RUN apk add autoconf automake libtool tesseract-ocr-dev

# Now comes the not-so-fun parts...  Many packages _only_ provide .so files in their distros -- not the .a
# needed files for building something with it statically.  Step through them now...


# libgif
RUN wget --no-check-certificate https://sourceforge.net/projects/giflib/files/giflib-5.1.4.tar.gz \
 && zcat giflib*tar.gz | tar xf - \
 && ( \
        cd giflib*/ \
        && ./configure --disable-shared --enable-static && make && make install \
    ) \
 && hash -r


# libwebp
RUN git clone https://github.com/webmproject/libwebp \
 && ( \
        cd libwebp \
        && ./autogen.sh \
        && ./configure --disable-shared --enable-static && make && make install \
    )


# leptonica
RUN wget http://www.leptonica.org/source/leptonica-1.74.4.tar.gz \
 && zcat leptonica*tar.gz | tar xf - \
 && ( \
        cd leptonica*/ \
        && ./configure --disable-shared --enable-static && make && make install \
    ) \
 && hash -r


# tesseract
RUN git clone https://github.com/tesseract-ocr/tesseract \
 && ( \
        cd tesseract \
        && ./autogen.sh \
        && ./configure --disable-shared --enable-static && make && make install \
    )


# ccextractor -- build static
RUN git clone https://github.com/CCExtractor/ccextractor \
 && ( \
        cd ccextractor/linux/ \
        && ./autogen.sh \
        && ./configure \
        && perl -i -pe 's/O3 /O3 -static /' Makefile \
        && perl -i -pe 's/(strchr|strstr)\(/$1((char *)/'  ../src/gpacmp4/url.c  ../src/gpacmp4/error.c \
        && set +e \
        && make ENABLE_OCR=yes \
        && set -e \
        && gcc -Wno-write-strings -D_FILE_OFFSET_BITS=64 -DVERSION_FILE_PRESENT -O3 -std=gnu99 -s -DGPAC_CONFIG_LINUX -DENABLE_OCR -DPNG_NO_CONFIG_H -I/usr/local/include/tesseract -I/usr/local/include/leptonica $(find ../src -name '*.o') -o ccextractor \
            --static -lm \
            /usr/local/lib/libtesseract.a \
            /usr/local/lib/liblept.a \
            /usr/local/lib/libgif.a \
            /usr/local/lib/libwebp.a \
            /usr/lib/libjpeg.a \
            /usr/lib/libtiff.a \
            /usr/lib/libgomp.a \
            -lstdc++ \
    )

# get english lang trained data
RUN wget --no-check-certificate https://github.com/tesseract-ocr/tessdata/raw/master/eng.traineddata

FROM alpine:latest

COPY --from=0 /tmp/cc/ccextractor/linux/ccextractor /usr/local/bin/
COPY --from=0 /usr/local/share/tessdata /usr/local/share/tessdata
COPY --from=0 /tmp/cc/eng.traineddata /usr/local/share/tessdata

ENTRYPOINT ["ccextractor"]
