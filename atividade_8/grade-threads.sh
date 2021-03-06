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
�      �=�z�6ҹ�S ��P�D�,��-7^Gi�u�|����ث�!�	E�e;M�4{�W��m^�@<�����
����0 �������A����*�g�&��=kV��azPk4��ڳ��z�A�V_�������1L���C�l6nV�i
"���{т�˿����_@J���7G�������Qwg�}���������z7�OO�����rn��s�
���98>��?h�Vj���G�'�Z����g;��.Yy�E,�@��#��
!e�;���-�e��!)�Ȋ�5C�<��D�I0�H���C-��R�=[�C�@Q]s((ӻf@�"�(�ŔPm���V�s�!�s)����Y��Z��¯-�;NSǿѽ�6p�È�0���7��߬n,��"�#��:c��mX�gv
j�o��t�����<���fl7 �U��G0�t^�	V�ł�G	Hw`�� T�*ȟԴ:8u`d ���1�
6���*$�p�!u��ҷ��F�j@���44mW����F��E�|
�����a�4�LL# *���[f��&y�Hdw��SW+qD�g�ZX˧��wIM�|.�6� ���E�"� ���]�:|{pP"��r��A�16g��982*�Q���'��HE��'Q1�����^/V���J���R!y������РW�uzZ�t�ju��\�:��ַ(�<�!A�'-�$
tW욎�u�Z	Uϡ��	*���˵vV��:!���E�@�b,b���������D��gQ3Q��5Y�&�H�G<�-�F1��XwbM�9��d4E��׽��sD��׸�E	#f���,�
���|w��U��Y�c���j����٪���;=]�֊i�ꧧ��~:[-��F�I�S�`�2��j3�c1���ta�7�D��e�b<��^���CMw<�W�����B&���CA�J��� ��Wq;ߊ��I�6[8Aa�r��:E�]��9�}�Ad^K��pr�g
A!P��{U'����*0�sL
����l��
����b�R8]���h���"�&�I�N��YŦ�#5��yZb�E��B;��%ʬM�$y��Ĳ)V�>��q/Y�+�V"~(�
��,�����uT$��#�������M��}�ތ9�v�)aV�i�輪U"G�;��Nڇ/�/�ć�����mPyE���@����$H�ê2M� D�|܃JCa:�Z-1�� ����O��m��f��b���g>c���ꘈ�ʹ9sE!����U�C+��F��R@�P���zo������;�EY��ä�R? ��:��u��'����G�<�+�F|D�J�'OP�LK>�H]��ѲTU�r5�
����I�`d��x�Ɲ���^o!5�ٗ��K,��ƞ�Xur-����c��b
5C.c�K.��A���ч=�!]����q�9[c˕0ӽ�3fE�)�!r�P�ܑC�Xf`�K�q��0���4��bņ(�L������G����O;.�Gfoh��A�Jn����N� GCđ�cO��vu��j؅�$[BC�}�����:S��o��7��>�}j���0���ǰߖ�UTQ��R+TI���Z�IO�y��Q����t���Ǫ�U�����tq(��m]�UDA��i��V."w�%������C=���d^�g�̡ Y,p�*�����|�KS9��pB�<����7(N.W,g
E[d7���(�T�݊��dѭ�@��ZE������F8PJrCicJ��"6�LSp?����5a:ڪ���[��� �\4�wi��� ��B�q��R$a+����h<iqU����k�j�%���}ߴh�Ҵ��kc��_����m6��e�I��{����^�Nv[+���뷇'�����9x}�cke���~�ݽ��V�TRv���j��?IR��E�;N���,�X�u�k�0�:0#� ���`�Ml��X>u[+:�*��V���#�M�4�O���g��+D�|�F���ޞ����a]N�؉��`�gP�������v�>��ߑ('�ؖ-6H���pa���̡tDV�����GP��ў���� E�7���
~������R�(Q�t-�W��w=�04ɗ�\����3��86�!�'����
���SR6UeWj���?�K�m��AE�����O�JA�x$[yk���֗yZ䊷��I�-T�b.X�<F,�p�28����G���������B�&��3�M��_���?h~yH�>�Y���,��76��?I��/�x����y������6N<�~��{�NS�H�`3�sm�G���Z���قq��P�OFӣ�:7��aR�+5r�+�RTvp96�a6v��U���y��y�_r�y�f�+D;�}�a��zX�!���q��s �>�2H�= ��=��ѣG+�M�PG��b�=R#ekԴp�U+F �zIl����/ h��M�� �ڊ���k�b1l$K»n��n�"@H 	�-i��]�1a1�^�x�-:�5��}5�Z`����~�i���{sԪ�s"m幖8Іp�Kt�W�s�P�,TC%>�H~� ��,�A5�G[��bx N-�FB����.gLHF��U���W��S����:�Sԧ�����U�%4�B>��&9��ީV"���0���V~�����A!6��S���q�߳SZ�nb��9�.�s T-��m�UN�j�R�?-jd'a(
�y�L��3�{8~����Սg��ߋHY�3�{�:p�o47��_Dʗ?�ޝ\_�͍Fs)�E�)�o^�w�ח�Fs9��f�����ց���Yc}9���?�2�#��X�-�z���_@���m��x��փ�˿^�X�������F��=?80���1���j�^[Oɿ��������O#����Sr6��)g|j�N^h�]o8�\f8��o�3�q��~�^[*���k�.c�r
Pu�P���u���/z.n�m� �8�c��͏6r��<ǡ���RQ�0�;v�t�1�Pe�I���V3��³-C ���)����x�u�0x�~ޡZ�ȧ*?]X/���~׿��:��l~
�m�u��'���"H~^wS��w�X�x2<�"�<4]�[�-q~h%bg��	9w�Wl�^�H�;zN�����C�C���>!"ô,a�De�o
�"Y%5a������E�F t~�,M��C��'�NQ�٢��&�!$�.pLhw�y��н�^��0U*&W���J��	��g�l$zA�A��g����-�/1�(��(5L���S�1Ҡ�C��.�Y����Cl�m�*��$��x��2�J�s�b������ԷMGWY�aԏh�
�H�z1q�|z#'~{v#���D�W�;<��Bм�f�iDi�;��yc���}����NJ�����3���j�ȸ$��t��,׮F.��Kn0�хvzS� ��T���4�*�Ԯ��4�4��&z��ܘ�=�H���{"'3&�u:)Gc��<�\���n�����c�9?F��-N���rEБ^���{��.qCk�]O'�OyG_UfVZ�k�z�̏uA�G�Y@�Lȍ���&yl4z�81:�d���Q(�HaH�Q�]�&5ccu�z1�k���������)��W|����\�/"M��W���K�/"͒�׊�ז�!i�/>�_}���YL����o,��B�M�Z������W�t��2���4W�������"JpB�^/�bd��L#��';;#��U�8 �#�ap^<�����mQ5���ND�>��l�tHX�o�$"�=���	��-�]��z�z.y�:/"tE<8fe�/��W���V[���V
0�ڗyZ�M�I ��N�t�G�xd��]堧�fIF�I�-�c7SK%��Z`��<3��{����b:"��b�'�`�JeEB|�?���� �/�rJD+�񦐆����$L2�4ǂ��])
����n�|V���1��O�Q����!����bI� 
��E�s^��t+�/,�m�{������ׅ�o�����+��kx��D���]��#<�=|�:�������f�����\�IYz��p�����r[���|������I_����P"iv6Ѝ�9��T�ǫ
��5�܂e��IS�}���,��%L���DlA�U0�2�㗹�	�@�#�-����i["�x�#�"y7O9d�%��U�]�+<�:N�����rI��Wx"66�AD�LD���N�_���6�G�)���Yv�Dx�$OO<�O:c��Sw ��&��5�g�"�OC�_�S�/C���{�[������gX��� ��h��<���/"-��g�����>L�P��x^���}�yD��/� �����t�F�%κ`@.��i;����0��Yt�I���2�4id��}j��ŵ�g1�����^VU����O���!�[�j(�T �7���El���^���b-6q��Cax/-G���	��q`y�X������%�D c�A����TG��2�KJJKjLB?S=;1=B��B� �7z�{�8N�����!7���Nn���߯�Q�<jh�Bzu��kUA2+l<,�!�h����;qv>���r��r].�&�ħ��o��Ã������F�����r�o1������st��[
�D�����9u0a3����S���ܽ��G��C�NX���)�P����Cp'|���s�ƫ��:���m�����G�������7߲��R�_v\]�=����^ ��Ώv�Xc��5�m�VW�`'N_Bw��p��d����}�x�ħ19�N(��Q���IL���=��sԛ�!rF^�=a+8��"�o�&pxR5>�(��<w�w� ���y�#���i�:����	���9��l`�3T��0�F�}�$�m��ۥ^/���;iˤ�	��4��_ln�iB��&�8F0���r�"�n5����oL3���z=5�[ߨ6��E����k������tm��.9��{�������ҍƿ93�H3�s��^�5�ϖ�!�������5L���߃]���U����h;r�s��1}�����Z���-�=�.[�X����i��p�Yø#�Rw<$�ᒗ�D�[���w�s��DF����,`��N���-a2�A(sqX\�t��}q�8����T�k�=y}�8��P�4�₈���f"#~ra�\��E�r�N�~�ڱMFq��V���ɷ�������$%fk1���˿<�r�aHb%�Ԋ��wJ_�d@�rCh��^`���} �,�L��{~32��!��@�C����ю�����oRI��W�#��-��'�1�/6p>�d\�O7�d`p',)΄w�$���i��ÿF.nryw�HeE��a$^�
�m�9��|T�-a>�㩌����"PL�-�����S���M����K\9�oI�#e�
�UM��0�ϲ�F��8%�uԐ��c%~b=w�F�F�4��%����W{�я_��6� ���p?����
���������\����&����s�H�S�9h�09���Q����n�"q��}ӛEnu��\�ɻK���$��z����4*�;[���%�.4���s��>iM�((	of��ԪF���#=��8^�u�1yl�����1�:ĿC��N���Y6�@4�30q�P�lm�p���Q�d�U��=��܏q?+���o����s�mL_�ժ��?5���\�-"m� �&0�e0$ZZͨj���zx����=yY�N�a�P���{�[ wYK�h�R��׆+x��Ueݨ"�y�����Ҹlp�:��۫�c�84�a�?L56�>�ܓ���q�,�Y�p<kx`t{�Y��Et|��mWyh
���!������v%,D@0�v���w,�i$ɳ�+J-l���d�H20��b-� fb6,��E�c�q7��w��\���9m�y?A2_��U�M���eَإ�꙯���*�n(������a)�
Yo���^4K�DE���l</�z|�>Ѝ�"�5��j��� �W�U���̅}����
�a�
��QX��"�ZD&�k��Hx_E��ί���Q��\x��ca���.xK@��|�ո����|o/�����Q�$�ĥ�B:�.�({{�D�bi��xlⲀV�+���J��T�r���2�wo�qg� |T�+�M]Ƿ+���kb�����c�xt☿7�5��m��46ۇ���}w"B�0�\,��rT�C�%ؠ��*�R�����.z��,���	�qe���,���5mk���H�8�(�)�֯���Q��U��/��Kp3/��q). Qf39�ȷǄM�?���I�}%�����c���V�*��1L��U��b�(�~���$x�[�z�3����r�ܷ�#?X	yP�=3a�T����i���\92avＴ�������x�7q�{����l2q,��o��<�Z��|�*z:���*}������NWD�B�+߂Q9�h8�a��)BN�������wY.��LA�馁1~��Z�EF���*�K`��]:.�+�_�S�`^��c��N���g||�3�o�6��f��<��&#��(�ӆ��.+�3�Z%�Ֆ3���H���,��>I�M����|��5є2_J���0#&�dJ�D��T�3�����5���u�5�+�(�ٯ+/��.��*�XIIP]$�8�л� ��{�ҕ+��A�A��)9H�����&f�h���i�ӷp6uwpmyx.[qVws��Sz�lJ�aJ�	�N�R�`�yO�+]wz=ֱz���_�_;J�T �g+��TV��7:�H\���Ӳ���7���?�����/�v��#k���ψPL2;��!�����k�u8��VJ�������?˞��x?���ϯ��K����38�9����$9��Ŷ��.��7cg���6������Α��c��g/��|'�b��4��R�_P���W�ߘr��y�?8`���L�v��XԀZ
׹]%O6p�ab���,�$���P��p�����;�cD�r�z��#�����O���ߊ�qD�uC�E|���@�2����e![��1.UV��y����}Js���#F� A� 4�k�b0Ά�Ko�M��tܗ���H�D�$#������h�����Y���d��4��o4(�휖{B/��F��Y	zȁ�[M4���k�Sڕ*�l|���}�c��Y��Y��_�z���t���I�(��p���3���s\�p�}����~�4����1���3�%�����������������i�R��<]�U���x �*�*�����*R� �U4�=3��-:[?A�'��b��K���*Co]��WO0Hl�Xt�n�Iۙ�d�:���H��<������U�6˙��{	� ������C��h�e-@ж��ۛ��4P�u"`��ˏn����BkOa�t	T�Vu<0d�ADZ��I��˖��H.$<Fc�srߢ�DDow���ӣ,^X�#�GAr��$Yt+ID'��G�ATTz��ah�F.#i4���˳F9��]�}��p�?2�Jr6cKnH+��&�x$��zV_%�P˥���D�Rh���H��x���Z=?YB�������s�Gt�3/�.���$b@��Oֺ�~��tzN�&���(�/�]�x'����k9p�Z@�i�*ꑰtvB��i��J��-�(��j��X)[���NOʙM)|ʧZ翾�@�EZ��S�$#U�C����R��h6������"����y���\�O��Z����g��bs5ë�d\o�خ�^G^0���T�M4&���Q�تi
�d�K� u�`�Z]�W��2����w����)恠\�vʡ���d6�o�n��_��w��˼~�*�;�`��"E�/�U|8 r�����a�V�M��Cf� ����DΨ�d�f8��`���4#�R��Z��V/k�G;�x\�:����z0�:ޚ�A?ՏO�s�����d�{N���ߥY~�@IXv	�O8`ȅ���;��*�4�iI1�ЅH��.>K}!ak�N����/���l�4 /����S��]}�t����|��R�>�s�0�f5��!��״ �t�EL���X�2:���CH\�$m�`�I�J>)�)��	�S�4��FɫX�Iu� �&�I�L��P�=O�*�+�8E|^Ækhl�b�uV�ӱ�N�<!'��!-�B�<���\En�|�'�y��ԅ7��Q�.������5�;}|ڂ�դ��:�?�EWZ"�9n��S��G�K��k�r�i��i��i��i��i��	�?	-� �  