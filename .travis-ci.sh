case "$OCAML_VERSION" in
4.01.0) ppa=avsm/ocaml41+opam12; ;;
4.02.1) ppa=avsm/ocaml42+opam12; ;;
*) echo @@@ Unknown $OCAML_VERSION; exit 1 ;;
esac

echo "yes" | sudo add-apt-repository ppa:$ppa
sudo apt-get update -qq
sudo apt-get install -qq ocaml ocaml-native-compilers camlp4-extra opam aspcud

export OPAMYES=1
echo @@@ OCaml version
ocaml -version
echo @@@ OPAM versions
opam --version
opam --git-version

echo @@@ Init OPAM
opam init git://github.com/ocaml/opam-repository >/dev/null 2>&1
echo @@@ Get branch of dns
git clone -b mdns https://github.com/infidel/ocaml-dns.git
opam pin add dns ocaml-dns
echo @@@ Pin and install mDNS
opam pin add mdns .
opam install mdns

echo @@@ depopt: tcpip
opam install tcpip
#export OPAMVERBOSE=1
# TODO: opam install async

echo @@@ Non-OPAM build and test
opam install pcap-format
eval `opam config env`
make clean
make
make test

opam install mirage
cd lib_test/mirage
mirage configure --unix
make
cd ../..

# ocveralls now requires OCaml >=4.02.0
if [ "$OCAML_VERSION" == "4.02.1" ] ; then
    opam install ocveralls

    #echo @@@ Installing OASIS
    #opam install oasis
    #echo @@@ hacking mdns _oasis file for bisect
    #sed -i -e 's/^\(\s\+BuildDepends:\s.*\)$/\1, bisect/' _oasis
    #oasis setup

    # run test, then send result to coveralls
    echo @@@ code coverage during test
    make clean
    make COVERAGE=--enable-coverage
    make test

    # These commands are from ocveralls .travis.yml
    echo @@@ upload coverage to coveralls.io using ocveralls
    chmod +x ./ocveralls.sh
    #cd _build
    ./ocveralls.sh ./lib_test/ounit/bisect*.out
    #cd ..
fi

