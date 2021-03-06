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
�      �<�V۸���<�h�	$JK
g(�-k(�Bz�s
��$
�ibgl����aκ���}����[���N����:���cikI{kkK"�Q|N��`��7{��l��㻱�^W���X]o�כ����͵��=���XJ�I�!!��!��E�p����>q��q�o2
n����k?���<�����]�^|w4f���F���כ�{�~w,�?�����`���W��hPz�����(��:;[����������*����Z\+�h���������^��Cj>)/��2�������2��AH<��dъ�d��[�������"������!�	�{R�c�������X���R~Dї??�!��&q��hLC��d�z���8�t����243���O�<�iBۄ�Ÿd��~ Z%1��檪f�=hY{ʑ=�&����^L(�W�{��XA�$��l�@�6���b�Ͱ����?~�����ˣ�����^�9z�A7 G�n���>��o0 �29���k/�<���qD`�'1��!-�`�)8T��h�������"L
7�`�o#��n��:��	� �>BM�����8�A{��>�k��o�34Gan�_�?���k�����&������C�`kѺ����p6��yaaa��Y�h�]`��'R�m�瀺=��p��W`c�7��$��ŷ�������hYv�aے�4�{�9��� �����ATb�jּ&�l�M���Gq�e��K�p�g�@�ݫ��V��~��x��NF�ş�¥3q�l���0�q���A5��VU�5�U�Y���,��a­����� W��@B����e��l�*�r�S1���G��$k8�� ��_�G��r/�<���8���ON�����r�0J�e�[iy�o`�>%�)SD,}�b�#q@����"���. ��k�1,Z�� phE���&?E+�������Ov�lk��T���3�t�����a-)[�	�������͍Fv�_o�����Y��~�����}�`o�st�t�'�����W�+�)-@�ƛQZ���p�Y���by���y�^�q8�@P�,yN|�x�[���'unX!�h�[�O����{PW��R�I_�?L����Z�`r<� 0܈���0���3�h72����� �'ݘ�I`5��[Eq0�t������|?�.|pn)��&��ʠEFSH
ڃ�9(����<w:�QaE�)m��Δ��<$MC�c�a��,��w���\V�w4���}�y�� \�M E��49 v����wG�sEgk�t=KST�׉��xH%+�o4���mU5�x�	4��'��xC.�Ua�m���A�R%8�*v��Llh7vÈ�7j����uP1�Y���4~`�9�s�i1~�n�9�6+b��=V*�.���c���x���	������s�����c��O�4�F`�qv6�`z�z�zC?��;��&�����2-��t2Zi���1�1M�<���z��y'=\����E�Z��<{�0�~D��żs����:�#r�!��;��`0ņ�z��˒P��m
h}�f��a������SM���i�ビ���n$E��A+v��(g���N\��}y�8|{p�������U��c�aI�&���Y�_�)�=:�^�α0ۏa|svR�I
����iN
�M�ҵ3�lj�Z5L��c���0�f���(���3/����C��¸ZY���\6Y"�_�H��"���펯,�Z%F,	�s��Jy�0��j��.��K�u[����0�Zj ��l�޼�O��T� �1T�U�`�'7��|&Ƨ�3$���i�ǲI�y!UYhk��0´��GR��r~hfꁪ22R�]�?��Rԥ��D��T�!����2O����I�Z�P�� �a�%���.ҝ/"���M9l�M��du*dJ'����Z�$�9�D��H!�Z?��D��&e�H��P,�b�����u�mVTe58��Ըƕ8/(w`�A�t	4G�� @j�3�`��t���اDl12���*�d���H�Q�l�J#�HB��N�\����u��@�2�CǣD��H%��0Έ�X�'�:QQ6�?�Dt:�RS�Hw��B�$���5K(�
��S�$��}�g�+�l����/E�	cDD$��C�i��{��d�n	��Ɛj�&��a��j.��`�t��$�<f�/@�j��J฿P<õ���� �M<�p�;Yi���i�4�X��!~�ל�����(�Dp�����W!~����ôd7K�2#ia�u1:s.h�0�.�.^u��w����A&���F6����t��O9q���|_�t~p)\�� P�Ɨ�,ǟ��sqT��_���7�M�-���A.0��} �m**��41�aՔt>}�Q?m����ET��
���L했Ź�MӺV;���X��!N� �&e�����k���.��Ԑg�[�qڽ8>�`L�G�ӻãW;�/mu�H�w�/0m��}OH !�M*�0���tv:oO�i��Ef��:��>������0bz��`��� �O"�W��g�f�z�D�:%ٯ�F#��i���b��q��?Q����kh^����p�q@�AQ��o�?��[(��Q^i��i~��B�E���Qti�g�}+5���si�9:Tb_���_�w�V(W�7���6n���_��/넬��c�ٳ����*�U��w~�����㫍'˫U�l.��bd��lT��rc�֗�<e�f�I��-o<Y��z�����|5�����z V������d����'��W�?y�^k��`��O�k�ym�>B���7\;�b*�{Vk��.�_��%F���S�z��ȶLi�όR's��t����9N6�y�^Ϙ -��� ,L�)'�3AjV�65�Qon� 
������ ��pl3�ѯ(bo��YkH'�R��2;)���-�*Ж�/ŘY7�?eoh�k�(Sao�� ��2s�����_�my��˯غ�o�RqF�?4�RM��1��c{�چ�q�=7$�\*�Q����e�ԙF�S}�i�oZ=���%IÏj�JUn���j�)���G�ǉ�U5��i�٘�Q	[�]6|Ģ��[fS�3X8�j� �V�{�ꏫ��fUԈ$�� S�Xt��� �b�b�\6��T���br��2��1����a jAk�d�"������t��n�g��Z}�x5��������wyL習m¼�_@)g;U)�(�:L�%��	Yo4M�����9��*v�Wd�S>E�}T<2�ԡ�a&�/�sIݏ�5_ơ�������	B����u�4Sҡ���l;���b��%c'�9�ÄO�����l�3L=���A��!��
������r�a]�\y\���oU����Qs��S(RU�
�����P�����yn>�����d���PKAU2Ĵ]}�`�e��6����hv��d�>=֩�ŀ�^�̷Ȭy��5i��?�@�
|Ĩn/3h�ޱ�A!;�x�o�cϟ�Yj��9�����ĜC�l}�������5�)��:�l�f2�w���)ffh:��N�w}�����>��wCcF��XkN��[���?�o�,�=�n쒀D^��^�0#j�\�=�]ύH���Һ4���;�? �ݮ]�kwڻ���st���h�����J,�Q}����2r;,���;�:�	ˏ�"��l�TJ�M�yw��fK���¿1Mn�+�|Á�L�8�a82f<�=�+ٞ�<��J�����8�cD����h��F�ɗ�qZt�`�
S0u��U�)�Z�]��xkѳ^��΁��P���;��}�{[d��i�W��>�>9:���}���]�s�K�71s���e��Mݿ�~q��8oO����7���/O����d�����=�mo5��'���gɎ0 ���W���~���-�g���h�g�cc����i����긽����W��ik�C���M�x�4[�0U��AsF_�a����7W�Q�^�Qz�7KU���Ʃ2TG���+�hM-�s�ƣ�JJ��� K��C���UI��؁�����Nl[<�RqËʊL@�T0UXY� �~�i�U�����w�}�����\�*h��{�q�8s�`�AN�����"�s)��x�b������r!P�|�z�����H��[8��'�BQA8�� G�CH�f,�ְ� Q)N!1�l����^�ҽ��F��O�:�
��SI���Ucf�A)]Tx���bQXde"�
���ة��ᚽ2<�,�U0��5G<�1lM���	XQ�j^"*.�f+Ģ��nn͚��7����Y����.���S2c���7�w��]3]˿>s;a�������U�>�����9�k�U	�9��������z���$�`�NKq�	�n0���6�%EU�x�N�-q�{�q�޲��g��m��xɨE�>�VF��4x��7U~��e�e��ag���j����9��v�Cʄ=�?��:qY�A��[�]�Y��8ٞU��Rp�09�>�+'΅DN����@2��7� 9'�~�i�gWk����>n�E�n�?(q�/��7L���*'�����;Rj��֒Tg�͛�6�^TV���;��0	&�,������"M�0
�������DYV�SXd��٩���q�`�9���?�`�^=��q��X��c�|��Cz��È�"�$7���}x�r�7�GO���0Ű���r���v�G=^x�W��؉*�U�w�TP}ca�/�΃!;�أR�����hn�#5\8�����G, O�ȣQ��!�z�2�i� 4�%�A�
7�C�ŷ\Yv�Y��lY�>����>.SB9R���p^��T�.kge]�̅`���x\& �@�ne�4�\�5E�Y1X����|�6$�"d7�?eڤ�6��|J.nW=�Kv�9��gt��w�\ʷd[���Z�-���,���*��dq4C⿨�n�E2q��y���VR�2vP%����>��K�� �bX��tBd�X��\�IfL�0��8�n��Vj.d�s3��s32���7a߄�d�N����ٻ�m�!�)��nBف�&��o�[i�߂���(�4\��Y3��g�Y����2y��
QK&wH�s�+5��}"�VM\����u����i)@���苢�9��;�u�1��p����_5�Y1�1��YW�xS��h�?���Wf��؉������B|��~��-�1��lU��+�1��*�Uy��� ���񒁒�XZ�6�m5e��ז�H��O�}O�p,|1��8^z^��_�m���X���K/0^.��_M��<�]���͕�5LrӅ
�`���o@����+��h*?*h�D�1�$���~��ő��$�e��Vl-�9�߳,T��H9��~ͨ0����Q�M!��P4Ó��k�pL�ea��OC���� �)M�o�#��i�<������)~����je�B��d��:A��������>����'P1�F���ib}�����,��P�'W����0vW%���o�]�|���ќ�2��T�ԠڝV��g���b�Ҙ經<���<⫫z�y{����-h���+~R�>�U�#�<��a�g�~`n��N�%�,&�S���%0�e���ߘ�U>��ʎț>w�{
�[x��d6��`��FT�Fe~ʺ�I{��-��t��������f�<0����e�7��&C�L�X���`���x	�c�ܑ�)���T�������!r�U�S�e^Xa.�Õr1�:oÂpj|��1�\-eK
����"��p*����$s��~��|��}{|����~�v..�s�G�7��d�k����b��E���$�}ES$O:;0$�Z)V
Ǫ�%�d��Z���쫍���������m��ѯ�U���I�y�ع4vr�qb?��tn✆�`��(�$�\�����u�>u���=���.�q�aZ�"��b�X,��l
jw������g��\\Z�6s�?��x�.0p�D�,	7I�*^C��-Kkx��M��Z���4b��@�ZW˅B�+��Y8M0U���P�E��T��X���?/|.�*2G��Lm^G���V���SZ�kS��I�BQ�r�����LK��9��MT���j�@��2���*�����0[J̟�(9��.�`1��Ӡ�����\<X�T"RrN=�|O�0�~2l��	ƴȜ��2W�)��T2��ju�]\�a���>�����`ۛ��.k9����-cu��ե:�Ksgҩ�^HHG�y	�$�*-����VFP2�Y6�1����VF~�H�a��9�pC�O��F]
��TsJm�]�m��g�Y9����WXs"2KsL)��c��I&�s�k�\��&�>���Ԃ5(�'1|�%����d���"#S�����\�g�f�9Ztq�؝�Ы�]d���N~-�.�_��gc�}L=g��q.W�9�
��2���1v�+�����$7�dg�3�y���	���hu�V��A!9裪�7^A���|�Q�8Z�A[���������g�1�����1^4ê1� +A��f��h@��:���� _��X?���Tf�H%C�`k��BCZk`L�5�=��7g[�5��-ڕJ�ɔ[���D�9CD�!Uf�RH�i��'`�*ۖ)�i�7}��E��jǎr98���32%
�s1i��o!�ȓ���;}>A��K�m���Ԁ��@�b��.錕f	�sM�']$-+�.��2���~|�L]��s�0}Ԣ
3G6 y��q���Ў�ʷD���S��x�m7<A(ۚ�t�T_�V��Q�]J��<5��fl)�զβ�7�<fȾH0z�Vy�C�y �<[�*X��k"�a�k�����r�'l��\�y��hEaK{=Wq�����6U���%�V݈:����q��i|Z,��rQߍ�k�E�d�6r�+�������z�oK��H��U�X��Cu�nQ$�x"6�M��O�c��+�	�^"�f�TqN����"�T�+PO88^��fh�l	RMX�X���0ЌVj	J����0�lZ�vM�0���*Dl	פ	_�1��i�QST.㔺���5M8a�t#��}�ug}����7%^�h����F� ǻ0�1�٦�����p��N�-��G��h��8����bO�gco˔q+��}{f��U��b@�>.՛	L�KKB舰�%=��BI���nŻ,⒒�	L�\j�!u2X�(���]�\N�`���]��7>W3�ǵ�g`n2 R�lJ:?��?�4I�B���r:l�� o>M&����t��?UKZ\��+Z���%����y������LD�5� ��*�G�H=�$�6��\Ԋ����,Ց̭�1L��������x  K��
�ݖ�f�t�PFw�tl���x�SD��Ӗl��aM��ʩ�K�`��S7b��&w�{�jI	I�V+gl�H�ԀQ��gT~�H�ђ=��u$yp���%�A�qL��;���x����e,Sc̪vSf<>4/�������a��� v+�xh����W� |Ox�����.��3�uY�6`^��^DU�4#������[Ԣ\2�\_5Z���`��
,�JZ9ܑ�q�=���Y�*�K�[N�`.���@U�D��~ڹ��W�v���B��E	*To@V�p���&�����<�\�ȉuֵ�"uP��8�J����:W�Cͪ��Dj���~��{��8"2���:��<�*�GL���$��w>�ߘ�S�w���V�A�?������vI��:=�<}�N�
ߴӓ����-����6�x[e�=L���q��������Iܪܙ&w�e��[bCu� ���ƪ?;�A��2�8��f�qQ^��:�*x~i=MWfd�r��Z��ښ��ƘAK�u�v�����f�K�RT��l,	UsFh�qX�DY.��wqU���7^���H���رt�xor�G����W��M����j��8>��m��b���v���)"��'xt�,�f�1"�^�[&�H��ڣ�N7�M/h3<���!���S6�3�U R��c/�E��0uu�<}���ۮW��3O:�ץ��|�z�i�(��9�jd��"A�`i�QF�����<�-�$��ڽ�n!0��D'�8H�R���l^0�/Moͭ$�<��L,*��j1���T��)���`ɮ�{���gl�ebq�V�5��[I|ә!�t{��Y��2�/�>���Ŵ�9��tqmm���q$>�z�ד��� e,D5 ��4s�P����~��G�o/�������)���8����Qv�Sw}#y�ã'���"e���K�ޛ��7@9�+FN����`��a���f���ާ�ύ"�X�����ҝ�#��Y���j/����8Șβe:�Q1�M���5�/�;��5�l�9����:X�?�-H���P��B�N"��V��R�Go��@�1D��X���D�����J+1�eg5�
:S�r�[[YP�Ԛl���/�,�������jչ�,XٽE':�(kT�we�>�o�Z�E������vn�*��>~����q�����"^Ʉ3�v�����u���;J�Z�p-޲⣤6&�?M��;g�abE���~J�2�����K��<�h��%��ɇD����b�v[;��a\��f��	��Ʒ�n�}AU"�;����v@��7����U��t�&�Z9DΟ4%�����R��i�B�C�{*� �I��I<+Ăl��c^�����ɥ譗O�Qa�
�Ú��ƅ�	BH��\���So:jg9c�:B�Z�$ �!�®j�|�w&:����,3.�B1�ʫU�^z.�ё�7�);�W�.Q_ɇg�am�m��o���e��e#d�7q��>o��z����#�^nǫ��<��V7S�{�Y��AĹ<=��{�&6��ٱv��r�f�J,WQ�B&�n�Oqh�����{r��b����Q�~%�|\O���O/���H��ܟ��r?:*��'��'S���Fx�n5e��PL����%��ɣ'��ߣ����NR��s���Z���/�Ͱ���g�n�n�@��7,DME���gʘ&3j��!�A5�/�"�{��?%ʘO/fm�Hh�0?S,"���}5����*H!�8<m�?yz���ő�B)��zS�du�L�V�A%Qbe"11�O�?e�yΩT�5�����h�7����R��B{���,
8c��������Q�*	|�:;o���6�i�U�����k5G��y��Z��� \BVmgQ��8�* ��Pk����%Y�����!+^���v�DbSV݆�6OG��t��=��C}sku)�x�K��l �}�ֆT�
!o�k!���ʻT7�ϫ�S�_��&�I��վ�&�'�O�!S�'F�">I�C�o'�_c{��DwW�FN�M\�9EV?�����Έ�:O�CGW���yR�ύ{���zܝ�?U��"����:=a	|(MK	p�W(��8(�a���BX%wLg��Jϭ`h_!Lu�}h\*��i�Z;U8�Zh�ֿ*�0�~e�J��sW�ŷ�[��j8���o�y�~���й�_o�HM�`�
�-�=�z�Ī+S-���gg�=D[�FL��~g�l����� _֔R�=-XF�tk��{Ey����&�1��M�r�CpR�6P�>4���<QpC����M����R������x�ŉ�<���=z�M�?Z���I�f��wƝ����M�ν�[�B^�+��v�3g-�Ō�2n�Ћ@���B����Ǉ�q"���:C>���m�ek߰�˯�e�y� �F�v!'R�5�ߪR*4q���h��vm0ao�ZD����X�Y��v�Ć,^ �bm���I�=qF��H�%�P��=f[�A�L��d�I���:&E��#�fL�f����Śuk��h�4#��v�D%�c���4|V;|w����7���W�qI���;���/ Z_�������:[����^^���l�;:[�/�����.���Y��:j���O�(�������b��5�xdc4 A{m�C>�PZb#,{�e�F猸�}h@c`�I������໽W�߲/B�d'�����	L �_��ek���&y���P�tN���I��������Q5�C��?4N���z�]��D-Ө*���&���r�DJ��8�gSUxF�5�B{	}k�pFcʿz���C~@���|�^R0���:����Iǝe�x	y����]p}>��h�2Nh"�| ���:h$��n�}�(��>�;x��D*z���WQ� 4D>v����:N�h���p� ;���"�Ƃ,������� a�@ +� Q�L �񅤈uA�hB9�l(�wBx^(l�&�x^@��Փm���r1���!�i�;�M�BP����Kq^_�t��4sT�����	�\�X���4v��J�T�����T�XJ��Ad���`�,e�T'X�\:�-�j���b���@�|�2G�v���|������P�H�)���g?N9�Gg�K����Y��AF�AJ���3���bQ|�G4r�~���ߦ�?6-���H�Gw�>����21�{S����|[�쭩���ԝT�3d�C����o����4z����+��C�D9�n�e�X��6Y�՛�� ō�x�6;�"���v�>�8U�Ga�F�ņt1�LQw�fl!�Ɉ�als	�)�2���'��bO�>5(�r�N�K���x.z��������z������x�"0L���}+�#0f���47r5oG�+��H����Q�2 b\�v�:ȥ���Z��U���5�I��Q�譺�t���f|��� �����7tw�����5�������#r�{3�ᨸH_%�󿲖�~%����i��G��]�/���:�n�0 �u�Z]X�������88���c���A���U�'
�U��Ni�ٶ�C�v�^M��|X�Ӈ�}���i����>�\V��{�����6��4���G��ϸKv>מp���0��q�̼�� �&P'䂉�$3���>w�>oB�<x���І������g�G*�@q�v:[�^��%ڈ.'k'������ sy�  �/u�����o0%��ë_a�E0 ���"U�B��z]ѡ͜�! ���L"��y��p��� >m����h����0��g����[�4�Z�r��O�3>澍��tɡ�7�h�m�y����0S9�agy�}<]����ZZ���0�:?#-���W;:x����r�3 ��o���h@�Zr�:�rSm&�b�a.���TCn0P���_("�h�9`������lҢׇۨx��I����">u��yM^�w.��֐�����&4db����l�u��=�_�P�}���a����/�_��R��FdSN��̅����U��ݽ��{�=�����Ð����v����Ǐֻ��x��Hvp$������op���n߱a�L}B;p�%B���cx*�/��F��;��M�6(MuA������9��6�1G��� ���7o�Sko�-� "v�:\�p3y���N�N:�6AT`Ww�K�ey�a�����v��Y=��X�v���ȒqOg1�<s��L���f��Q�EUn/;����U��~�q4�E,��#�B���O5��b��{y�qg���G�&���:A@�Nr�%�.�Z�A�tQP<:�N< Ŕc�dE�K0�~{S���>���ۿob5z-T���d��  \plM��`z��e`9�J�5ե�'��5a8�w_����Ь����8^[���q)ʠ=�Ev%�i��bl{[���b��_ꋚ*�ݦP�x>��l1��^bPܮ	Bǯ���D���G��v(��¥��$������wJb��C19R5��<#�ɰ�������^Q$U�m�O�\�*#��Ì9��������$��%Q|�~E���9������$,�t�PW�v�"���1�~�	cF�b����+k}�}����ٱ,�������-��E���4�vϝ�^�O��3]�)���@/�#��k���8���vA˟�D���Z����̽���y��$3p�2%?T#��&.�_��&&W"
���X�w܉��Θ�VP�a�Y��@_�����o�T�h���D��c
�Rl��=J�/��/�3s��Z��,�S1����x�f>s@/@r�V�^�Ҋ�e�ɶ��C.���)�T'�CJUM2��C�( ���ދ��6cfc�J���oCCyy-�W
<025P�����W7AȘv�@? %��POl?D
�n4hj���D��&��p�R�i:j=��Bh�i�i�i�i�i�i�i�i�i�i�i�i�i������  