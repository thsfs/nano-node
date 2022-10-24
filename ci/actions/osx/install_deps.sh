#!/bin/bash

brew update
brew install coreutils
brew install xquartz --cask
brew install openssl@1.1
brew link openssl@1.1 --force
sudo util/build_prep/fetch_boost.sh
util/build_prep/macosx/build_qt.sh
