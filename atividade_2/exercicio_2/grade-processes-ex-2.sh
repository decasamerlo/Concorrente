#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
cc -std=c11 tools/wrap-function.c -o tools/wrap-function \
  || echo "Compilation of wrap-function.c failed. If you are on a Mac, brace for impact"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
�      ��R�H6������ll�$X�0����*���ŌKHm�B�I&����}���yڷ}�����H-��fv�� V�����t+fQ|�|{�z鬒:������`���W�^���j4������f�A��=��1�b+�gy�܍f�]���tĉ�� ��7�?=��#o���U�cߎ���%q�����F����Z�A�v�_>������z���GV4(��j{���޳��N��(<�y��M�Q�!�]���C��&8A���9T�;���&���;�v�}(�X30 �`<#�Y0?���}g�P��n��w�?�
շ��3Ӷb02����FƵ���5�$� �>�̋*�8U���6�-�K�;��ﯭ���������К�����o{c��ߢ�q��`��O����s<�(;�cvNS׏!<���p�{��/zq�(���%{`�e*m�Of9=ڂ�0���p�l�Y��-dU�b��2?��B7f�id�����EC��M�a��vBNK�AE9�^�BZj�������6���|Aw���oT8���!RS�B�Cb�SA�@XB�b���r�C������V��*G-z=b_��tR_��IQ
\�&3Vj$�
(����#�K�k�W r߳���U*M�r��vu����q�a�T���6z=�Z=cs*p����� �g��$(|0���|ar��my^`��
���|�3T�����8,%f�1Vt�/E�"�Rjb����F{�HR�<��Y�̬����$�V��Ϸ��Uʋ��N��|&q�	OI�Ô��ϰ��N�jJ�L��F��HmhMA����1����~���z�a�|X���ݲ��R�Pi�k���\�v�ݤE�(x����`��ݩ��j���Z\ңg�Y��n�� ����GӍŝ&g-ԯ�I�pB��>f��4|]ݧt�*ʗ	'���꧲$��A�݉ȶ��x����ȹ�V�pv��C
��T�Ap�؜��|JY�8���./#L�n���J�HJ�mI��Y���,�s������H�&���vJ�u�(U�H���D�դ>+R�<�I,���w�z5��[��C��xOj�B)t�4_�#I��	�k:�4`���O7��U�)
�IggǄ��K��
��<�u~z��{�y���:?���u��5�#tT	�*	aE� �ºV�
v�w4�㢡�b��)b'��E���@U��!xU'UͼN��K��H�ʵye!�#�2�)���G� ���1vb�G�:}����C-�w�<�����a����\���&S��}N��i�G��^Z"ϲ�\�����(��u�r7����ii/ٷ� b�R�>�ԛ�OW(��Ф�ד��/={M�EƓ`�9�T�0)ϐ-b�y��I�4i�DD�\ S�4�q�Z�ȕ	���7���s�#丠4[�� +��̊�Vc�C�@9��6X�!�t������0�"�[!����(	{C+�D7�2�Y��iO'ߠF���������&	RV"��I�w�MXY���}fus���$|7vC���/1���Og�JnG�*Y(�u����Ar�k���8�5����6��qNG:�?�!w��nw9�Z���u�g�P@��˛p	�+m��ZvX�=��dd�|⇜S8 ܹ��_��Ga`�(�5��p��i�OQ��7dNn_4���-R̺������]�-�6]�DnWVJd�ptMm_���N	�imY]�S��Ti�gH���jO�m]rZ��j@s �U��\̼�	�)O!L׫E���L�E�x6���B�}@��G���8�V=����h\u���A��w}�>���������<�k����7��b����۽7�bK�����{�.��u:O��~�C��^ ���FQ���#$ �;]�Ǟ�/]qO�wP�8��\�16�"���X\T�����=�R�D��Q@�XJ.��~E�2bw�x�bш���t��x�`l�Z������O�s,_�tr�x-��o��U,�T-]���ŕՇ���*�hԽi�-�]lJ�D=	k��?��Y���m����ٚ���w���d��������N���7��_z�xn
�N��0�3�}�/�(�����J�V�~}�Oá����Ϙsd�'�aҸ��A.o�u�e�
#E�'�h�ż��v���� ��9ĸ���vC�
ɍ�1��Xu�T��p���|g���.b	�Q��`�1?~���Xll(B�����T�Ѐ����f9m�a��Wb�W5���{�IĖ��J�4,vb%Ed����7�W1 ,@pJF�㎫�*L��/�*(�|'`\�G��q�*�C�8���ߦOY:?��j��dd�Z���0|q����jNB�t�3����/����B=As�{��k��0��dW��ք�\1��,�2�"Q�i�#�\.-	I�ȝ���/"F�WYgH�>�S��Ԛ��QN�Q��(>­��7B�l���&ƶ�N��!nr��8���o/8���&0M���kE��ځ�h�[��WW��KleE�����H���幎�Z4�e���Fs����k���<�����ہZM�\���I���%��t� <����4�'�n;��T��	��/܎�X``2Š7$\Z	Kk��$���,�𞅁��u�L��)^`�ؚ�H�����&)x��Yh�������c�0xQ� ��_N��3ۈh�������G0�p�ưabN�u��s�Iaa1YIJ���#j���)��u
��^b�{�]�s��`��ǅ�zBRE�Dg� ���@4�Z���Z��t��JԚ*QĆ�K���k���B�d�ژ0U[F�>	�
s��^�H��<�E�R�XQ��*;QL�L7*�4҆�����#,Z�b�ey�t�2�V�Y�>�W��G���s�[N����9�Y^��$s3)�r�
P�p��Å����S]�\������g1�G�P|ݛ��Ե���.~�]&F��q��غ��vR`ѻ1�]:����(���w�A�B,/��"�f�&h^[��#.:ʀ��&��P��'o�5�O�1�\(PF�{��= ��d�v0���/�*��g6T=Y<Q���p�My
d�(o�9JIEȱ�����
55v�1ͩ�0�&$?���SuL�S�ֵz��0������*�[OgT�)v/�`��B]AA�9֎s�����w��-��;ħ!}��,tЭ+X�f1�ف�����������0ע�ż ^��!v�!�
�ſ��}�Ar2�x�d��wc������C��7�6��\�g~� s�c���Q��S��LAK9�~H�
����w��q0��5v� �`Al���5طB�_�m��q�����qC��W.����舁V�2����=�)*�`��#�7�5"Q�w	�*N��T[˧�R4L�zOZ"}�p|�i�C��X^�ݘ�?�N�T>���O�\�����K������\�8m���{��'�jŨ�ְ� �(8
Q\�$ˋ_㓽��rR���Ih�kņǴ���1����hje>�:e�A��}܌��_����ޓ6gө&�h�V��M�K�k��ncug�O�³��%���ѵ��JQw�kƉ��=Q	'O�D�y��Y�{��狏��N���#���3�OJߺK�<��(����o~��oL~B��/Q���甿��u{y9�Ğ2f��XŁ�%�~&��BA���>h�
Е�5t%�q&6�n��q�*�)�M䱰���Fqi)��ւb]c�Te9"��������o�I�8|����xP^SÐ�����SZ���8���s�/� s-C��FQR5.+L�U�AKe�IV�=TBDX���D�3��B�`�r��3^�<N�_���G�I|���U�)�D�8-����:�3�u���=�f �[�&\�EӘ�rQk����j��v3Rb������-јr��]��z�����|��|��|��|��|��|��� ��x� P  