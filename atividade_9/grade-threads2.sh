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
�      �<�v�Ʈ}�WL5&e��|I�8r��r��qrl��:�+��HbC�*/�����~�k?��	��̅R��i�M��,�`0 ��@�h]Po0n~��G����~��R?e�������o����Z��l�y,�-#+ �˥�NX���ߴE��#�w�?�
>\��K�����U`M��D��}��.����vN�7���>��������k^8^��
Ǖ��v^������j���t|�iW�~@��K����-b�B�!9%UB�7�"g[$S�D�=���J5C�}��!�,��Gd�Ǟ}O���ND��a���
ճ&�3}`ED���-��i�j��Uqr| ��(|�nH�3A��Fe��l�}�6w���O2��%����z~�o�-���h�o��6%O��v|s�]Q_�7ʿ�]�"�.�#z��*���?�'SXS:��G5b�Q� �Dd0�� [�Zv���L�h � ���@��:���b�6��P/�'��cdQ#z�8ib9��_�`4H��K���^N�Nr�C��KlS`*�������ː$~��yZ�:m��h+�Qx����V�� �!-�� �Џ���>8�������}�]�ç/U|����6y�a�ĉ�_'�(��IH#�A�MZu:�S(�e3��@���6�$a����Y�A̊��z�v��^��m�!p����A��uJ�ir�����1�\���:��K=�1d�U����>3���U���%���F�b���������̤N��g����a���,e����OK��O?��Ԓٛ�`f,E��*�����P�� �K�p�g�VD�������~j5~�i�o��u�vV�/���z5�m��U����_ޝՌ^/YO��� ���2��|>3oA��Z	�T��pf���O.��xZ�,f49m�|�N�g3◊-�{=#Ȅ�?W�8�*J�'��b5`�����w1*��h��:J&��];S�@��UM8���.��m�
Km�M��簄B���HF��Rju���4��	i��;7U8!�d����e�к��<���D�ڄ<�B�̡	*��n0�4����{E�jG"��{��)Ђ�G%���o8��pjߐ6y����e�2��)ᬱ���jp]'G�����'�����>v:�?��+���0��� �:g���-%M�� D�"҄�$��Τ�3���P�/w^�=H�y���3˘����T�L�wb�x8P#C�"C��n�@�J)}��,O=�v�E2I1��Q4F
u]����ݓLj�Ҡ��r��Q����,��u�@�a"z���Vf�V�t2r��sA��tB�>���H-�����g}�PX�:�i��ص��R��!6���e7RʢI�Q8�!���cT��L���ʸ��Ѝñ����8 �9�mE��B&�f�qvB9��bŇ(�CE.���G�OC���{a|�����8n�+o�5��;����S<}�/t:�q"59��.FBG�}�����6�lBl���������m!��飜�-d� �u� u�9�X��Zc=#�)�W��l���өʟ��Z�L~��[�wK=��h֐i�����\��jGH����`ҧ>`�_�~��-;�,� E�i�*�� �O@�P�@^�s����q&ޠ:�B<���$k�l�9��r�>��������.��Q�w�7Q���6��,�)c*4� �3(O�Xl	�ɶ����j� PrQI�ʁ�+� �$�_"%�3����Y���t����?����G�e�ƕ�D�n��kk3��������������W��x���=8��T�*�^�><�T���������Fe����v����f͇4<�U�[��ܐ�i�˦�n��:aԷi8��m���CFtIt�?��[.�bǵ�u�:d�L�C�)|�m�)����W~!���X �w{�f�3�;����a~����>CJ�Z8�n�<����I^ac9��4���*S��]J���T��-<�!��DuH�vo�(ƿ@#����|���\R�D΄��@�),���z%$�L�x����	����/��ͱ���Dbwb\�~��Gآ�? ]�9%K5v�����YZ�c`~�v�����80`��R�,�a/�Q^���B��������-�0N�S��g�}���	W�������!E�H�����S:�T؋�fP�7j��,�1����b�E��Q>�?|�����,M����G;�����'��G�8��V���q8M)�.�	C̵��Fc
{V_��^���/'3�Ծ�o�QR�/u��V���\�q;$��c�0v#v̅�ک���SrZ�sዜ�{n��$7�#5`��~X��v��� ?�.�4�c�y�ӧO�߿_m?�`
kp�LcHڤa?��1�l̶�F� `�%���/�� �{�ˆ�,�E�ժ�K�նa�AfY8���Y��"��6��)�Z4�����!�ؑ[R�5��}5Z �	&�q�*?}���lݟ_uZiN�U�j��6��c��d�c+�6��2�^��1V@v��c��L��Ѫ�f�8�;YA����t�`$ٱj��Η�1CJ�|���d�)��,�>�ʺ��B�;~�Izڗ�ڰ��	�R]&��,M�fj�ڐ�TLm<�ă�8�@��i�Β��l��
9�.> �V�]�6{f��l�V�lgEe�w��������=�=�7�֥���XP����An����^���Ѧ�F �^Ɍ����"�ұ��|�Upp�F��cj�
��^h��7Z7qWgG��'<��R��='2k��5� <U�\3�=������] �Ạ��ɉ�)Wh�f9�����Lm����O:��!�<v[�?q����;��0��9�陯�i�o�8S_D`��P� ?Vd	!ib���b����9p�04*���L�D��*�E���[ ·���K\��'��"��=�F4HQ8�K����]�ʃ<&�UH��:eyN�H{� ��TP�;=�{.�D�wC�m� Yra�-P���'�=zE ϳ.\���?}yI����L��7Q!6�mI��1^����A_o��j�%\DG	�xQ;�3�|�� �n��pN[g �(���Y�[�D|�2׻�4 Kf'@^�Nr�{�W���1	�qd��!1"R!��`:�z��r�Y�Ƭ֝�X���~¹�g�*֍KFR��A2J�=���o1��}D�3��������,�#��˖��D�~��Hx��ΖX,�ﯱ;��6�����w/_�?���i̕�����6��`�������ۊ"�"�������H����[;;,&�9�g�����w^w��E>č��������}l��ͷp�w �-�g�/r�������D�l�me(L �ZO�q�*�-�`@��8�v)�2�i�z�:b\ ����Չ8�,3ծXM�	lClr)w��C7T���r]��O~��?�G#*�K��qE6_�u4w����,�V���;���3����LF�0��(^�N�nV6�ӽ��4��6�%�/"��Ux�A��+@Mޙ�"�ǐ�2WWL�]s��;��>�������#�,C�+z��A�!N�yLګ���#��^<$#��jZ����B[�r)ʲ���ڄ%��[�|���~��s��^ӱ�d����˼�-jI°(�лLDa/4�0�\���۲���F~���W���ƹJ�4�H�)����8^�#�{�%W[�9�",N��j��/��LN%[>�
��rS�VP�Cp^Jf8?���&�F&�TR�����;�W5Gd�e�<*�����������%),۠-L��Z�p�z1M�1���1���D���1z��l�4{�ԉ���5ulF;�=ǵ`#���@�w�AV��Ħ7H�؉|�́YX@4�:םj�/پIv)�3�	�#!paH{�"�ێY(9Z��ĥ�0�6��j��U�MB�d��@=!�6[#��qȝv'�`�.u�"ӬA
"��ll1��Us��%��v~#�#f���p���蚌Bx�����w�KEl�aὖ0�z�5ih~B��ؑTjBZ]��R�n�&��2�S�t�Ηv�v=�����{��c��u�N��{��r�7e��&��/�(	��%��U�Ν �1]����N)��{��D��^O�h���cg2u������豹��k�$���X�R�@�XK,�5O�^wK���g7�|��U��l=;=�(�ֳ_XN�"�ʯ��Ȝ���
�3RAuuy�ъH>�^���>�U�;�Ӱ���CB]�d���x
�,��?�;����M9i��gf��'��2v�������Fo�Đd�ʳW �� ǯ;���'cf��Q�E���cNAQ����/����i������za]��#��9U��1���|�mI��HJ	^�@"@��cAШ�	/B��?�ݬ�D�)������/�#���[p������x"j��O|Ǵ��g�5���ll�o,��>GS�61��`JR����`�&�l�S�"h�mW3��j*�.x�H*0I7�O�
�t 	����������=C߯�|�w�x !�&�W��!�&�����$�@ a���/�*`#7���E���{ҩ~SeZ�g�z�,�MY��{�4%Y�HU�g������r��i����T@��w4�L��Uf�#���G�{�lE��#D�<�xɡ���؈�c]�"�BSVZ�ͲE�'�Q�q�۬$!!��(�����[B�:�{�k���W���5��l�7;W�Ę�'�\N��'ǝM��=:�_�v�����t����W�]�~qЁU��:m�g�&�7
�s3�����'W�sA7[��	�~	;@9�Y��6T�@��I�{�b�#_�5!�b�_�e=��|�X*��T�����B;�~�j|}fhf��쵛���I~��$�Gg?ٽ>p� Z=B݉��L�H�ƙN�}le� Ό��I���VcH�8IU�J�((U^!���UM��������c4y/��ZP�>��B%����Cꡲ�ԙ��ρ��b\=)ߛYș���&��:Dk�T�F����J���J�)1��-�o��[p��,�h��R�r�����(a���7	��Ѩ3���_���H�N�~Nz��6+J_�j�$h����_Yk�g�oJ�~�o6V�:@a���|��`@+��WP�&�/�;;LD�(�&�̩�?�:$Dw�<��7�z�7���M/�h�\9ol��
'���9��\�����0���:?'\�l��^��k�N_�D���\��ڹ"9�RX<73}+�9c<_YA�Yȯ�*/Y�P���X�1��>�XP�1� �L�q�<C
c�)����
�P�c�q<�{��Cp�R/J����r��@�'��|����A��9�7�x�]N.۲-۲-۲-۲-۲-۲-۲-۲-۲-۲-۲-۲-۲-۲-۲����O x  