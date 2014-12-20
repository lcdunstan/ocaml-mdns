case "$OCAML_VERSION" in
4.01.0) ppa=avsm/ocaml41+opam12; ;;
4.02.0) ppa=avsm/ocaml42+opam12; ;;
*) echo Unknown $OCAML_VERSION; exit 1 ;;
esac

echo "yes" | sudo add-apt-repository ppa:$ppa
sudo apt-get update -qq
sudo apt-get install -qq ocaml ocaml-native-compilers camlp4-extra opam aspcud

export OPAMYES=1
echo OCaml version
ocaml -version
echo OPAM versions
opam --version
opam --git-version

opam init git://github.com/ocaml/opam-repository >/dev/null 2>&1
git clone -b mdns git@github.com:infidel/ocaml-dns.git
opam pin add dns ocaml-dns
opam pin add mdns .
opam install mdns

opam install mirage-types tcpip
export OPAMVERBOSE=1
opam install async

eval `opam config env`
make clean
make
make test

opam install mirage
cd lib_test/mirage
mirage configure --unix
make
