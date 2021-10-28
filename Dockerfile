ARG VERSION=2.20.0

########################################################################################
# Build LilyPond on the latest Ubuntu. Unfortunately compiling does not work on alpine.
########################################################################################
FROM ubuntu AS build-basic
ARG VERSION
ARG DEBIAN_FRONTEND=noninteractive
ENV PATH="/opt/bin:$PATH" PKG_CONFIG_PATH="/opt/lib/pkgconfig:$PKG_CONFIG_PATH"

# Install Build Dependencies
RUN apt-get -qq --yes update && \
    # LilyPond Build Dependencies
    # See http://lilypond.org/doc/v2.20/Documentation/topdocs/INSTALL#other
    apt-get -qq --yes install \
        build-essential \
        guile-2.2-dev \
        python3-dev \
        autoconf \
        pkg-config \
        bison \
        flex \
        gettext \
        make \
        texlive-base \
        texlive-metapost \
        perl \
        texinfo \
        fontforge \
        t1utils \
        texlive-lang-cyrillic \
        libpango1.0-dev \
        # Use curl to download additional resources
        curl \
    && rm -rf /var/lib/apt/lists/*

# Build LilyPond
WORKDIR "/build/lilypond-$VERSION"
RUN curl -fsSL http://www.gust.org.pl/projects/e-foundry/tex-gyre/whole/tg2_501otf.zip -o ../tg2_501otf.zip \
    && unzip -q ../tg2_501otf.zip -d .. \
    && curl -fsSL https://lilypond.org/download/sources/v${VERSION%.*}/lilypond-$VERSION.tar.gz \
        | tar --extract --gzip --strip-components=1 \
    && ./autogen.sh --prefix=/opt --disable-documentation --with-texgyre-dir=/build/tg2_501otf \
    && make -s -j$(($(nproc)+1)) \
    && make -s install


########################################################################################
# Install runtime dependencies and copy the build artifacts from the previous stage.
########################################################################################
FROM ubuntu AS basic
ARG VERSION
ARG DEBIAN_FRONTEND=noninteractive
LABEL maintainer="Kim Wittenburg <codello@wittenburg.kim>" version="$VERSION"

RUN apt-get -qq --yes update && \
    apt-get -qq --yes install \
        guile-2.2 \
        libfontconfig1 \
        libfreetype6 \
        ghostscript \
        libpangoft2-1.0 \
        libltdl7 \
        python3-minimal && \
    # Update Fonts
    apt-get -qq --yes purge --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build-basic /opt /opt
ENV PATH="/opt/bin:$PATH" LD_LIBRARY_PATH="/opt/lib:$LD_LIBRARY_PATH"

WORKDIR /ly
ENTRYPOINT ["lilypond"]


########################################################################################
# Install Microsoft fonts in a new ubuntu environment
########################################################################################
FROM ubuntu AS build-fonts
ARG DEBIAN_FRONTEND=noninteractive

# Install Additional Fonts
WORKDIR /build/msfonts
RUN echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections && \
    apt-get -qq --yes update && \
    apt-get -qq --yes install \
        wget \
        ttf-dejavu \
        ttf-mscorefonts-installer && \
    rm -rf /var/lib/apt/lists/* && \
    # This fix is taken from here:
    # https://askubuntu.com/questions/1163560/change-mirror-for-ttf-mscorefonts-installer
    awk '/Url/ {sub("downloads[.]sourceforge[.]net/corefonts","cfhcable.dl.sourceforge.net/project/corefonts/the%20fonts/final",$2); system("wget "$2)}' /usr/share/package-data-downloads/ttf-mscorefonts-installer && \
    /usr/lib/msttcorefonts/update-ms-fonts $(pwd)/*.exe


########################################################################################
# Copy fonts into the final image.
########################################################################################
FROM basic AS fonts
ARG VERSION

COPY --from=build-fonts /usr/share/fonts /usr/share/fonts
COPY ./fonts/*/supplementary-fonts/*.otf ./fonts/*/supplementary-files/*/*.otf /usr/share/fonts/opentype/
COPY ./fonts/*/supplementary-fonts/*.ttf ./fonts/*/supplementary-files/*/*.ttf /usr/share/fonts/truetype/
COPY ./fonts/*/stylesheet/* "/opt/share/lilypond/$VERSION/ly/"
COPY ./fonts/*/otf ./fonts/*/woff "/opt/share/lilypond/$VERSION/fonts/otf/"
COPY ./fonts/*/svg/* "/opt/share/lilypond/$VERSION/fonts/svg/"


########################################################################################
# The shell image is useful in CI and other non-interactive environments where you might
# want to execute more than one lilypond command.
########################################################################################
FROM fonts AS shell
RUN apt-get -qq --yes update && \
    apt-get -qq --yes install \
        make \
        jq \
        unzip \
        curl \
        ca-certificates && \
    apt-get -qq --yes purge --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    rm -rf /var/lib/apt/lists/*

ENTRYPOINT []
