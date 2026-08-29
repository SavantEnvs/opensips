# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for OpenSIPS, built ON TOP of the org C/C++ base.
# The base provides clang/llvm + libFuzzer + the build-contract ENV
# (CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/SRC) and already ships bison, flex,
# pkg-config and libssl-dev, which is everything `make static` needs — so
# mayhem/build.sh installs nothing and the air-gapped re-run needs no network.

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
