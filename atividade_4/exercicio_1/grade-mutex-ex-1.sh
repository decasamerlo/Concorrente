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
�      �=mW�8���_����!����]�.g)������I⧉�������s??��O�?vg�bK~IhKٽ�A����h4�F�ȍi�S�?Zy��R���>�k�)ӣf{������n�?j4[���Gd�۱��i;!!��1�v�r�y��GS������h���?�|���H���
��>�z����;j��_]of�}u���4����߼��<^9w��s'U޿�yspܳ_�t;�����ǽN�2�C2tǔ�Y�a��
!�B��#i��-��e��1�ɂJU�!��G>1^"i��c2����!A�ݘ4�����
�s&�3����������d!�5�q����Q�A�e�\�
����v�i��_��I8�������Ws����0��#=q��x:��(���h��f��w����s=/���*������� Ɣ�
�JQ\#}�Qb�9a�����I���C�T'#H���W���ơ�������'ԋ��Ѝiq:jL��!M�3�^��
���"�K+gb!y�!m��) ��i����I�F$�;�ĩg�����&�BOC�4y�M���0$�����F�4���ể����A�c�W�X}���3p��I�'�~�H��xB'��Ť�4j$r��Pv�e�@�Z1(�]Y!	{�e��¸	�0�U�uzڴm�Z��U�B����e�K@���n��6��dpV����٬�ꍩg2�,�$�Y�6Ϭ�[KҒJ����H�i�]�<	�m���̤%5�e��sL^��7y��0����wK�me���N��,'Q���$�a������C��Vr_]��F��HhE@(�_ONcrV5O��o;��l�_�ճ*�,�;=��_KVN����ɯ��U���d4)V�3\6>��Vs"f���ke\T�ge��}�SǛŝŔ&�[ _�'�YN���T��d�me���w��p4��ݒ�\�|X����b���y�@D^G�_��3�!	�!8��.紹U��ܤ�0�����\�F�@��>YIM�IJ�m�W^Kg1�|Ge����DͮG6�(5m��)r.)NU�SIE��jB�5!kf��M�)�ƻ��W�[-H�d*�'�+�-�f8*��O��̧æ}O�d����󓥳�����$c2��F�v_��_z�ý���r�}���W�ɡ��) )?D�5�w
�s���|:�	7Hb��9�9b��{
����/�8���D�����R�D*U&͹��n���!Z��0{� #4d'F�~0��N��ݟm��(C���t��BL�c����ݞ�A+�4,���h"G�]������{�$�5h�����v+SC�H:�9u�� ���ѴB�>���[>�������q(4֚L��]:�]!�$5C,S�ӗOʠIWOX��!k���t�c�3���K3���x��.�H��UސC���!WNĤCk�4����]+6DɎ�@�g_��4��I�o�����yb�&N�a�	���JmN�t�$*	'
�{w��obC��	)pMԄ��)�YZR�Wufe����S7�r�)�)�➣l�@�*A�:A�Hu1_'�2ƺ&��+�j��4P���Q��?;=}�-��p���fI�:y�x���K�]�)� ��r8��X���׉ܰM�PĜv����x�}E����qPd�d�����u������-���F�L��v��򮫚��Ғ�]���m��@)��6&]��1�B��3(Ox�ׄ�d��Zvl�3 �(���w���+�@��$�_"%=<�&>D��W�/hz���o�����3��+Ǎﮎ9��V��wm��x�����������c���Ao��Ъ��;�u���}pt����Zy�������sga���C�1d�A���$ +z��M��Je�F�=�Q�z���%1�%�y��Uvǃ�z����Ow�!�z O��i�g�V���O"$�|�J `�lO��q��|���'�i�)�ja;��y툾����7$�B��r�iD?�֙�\4S�������+(�N�ɞ��? ř��JNw�<��Q��.����Fo���JD��Ӿ���l��xe���fX��t"�[1.Y�q�6(�HdNI�Q�]��ǟ��V:�&0���`q�.TXQ
�A�x"jy��^>ן��ɤ���FrjR��B"�����������|:\>���r~?t+C��
�h��^���x�ͯOhxAû�c����������?���������^�>z�c�?����V��bz،��J@�0	n������:X|��{��J��̐�����0���X�[��Υ�#Y��7��8f^����������3����wa怿Jr�A�:�:c\����C� ��Xo�zws���?<y�d��i@Z8����4I}�	�#���jZ��������	 ��=VE�c\Z0M	�Դ,YI���_7Ϫ���=���-�k^��3���b�oI �L:��k���p�gt����e����m���D���Іp��5�!�[T+�V�׀ۙ�7�
��PMPԄ�c�5, �'�!���5�	F���U%����<��)R���"o�*�S�&��mh�sճ!��]Nrj<]nO�a5݀��$`,|CӣZ� �6�2�.���#�iL�#pj��K�Ҳz�&|vS< �V��]�,Z9]n4VV.�Y��E���)��ϧ�f���7��������t��������-���Vk#��j>�����Co@�Ķ��s����;zk��ǽ���?�?�v�	�:�3 ��P'�G�fKq;�ŋ���D����� S?S�hmU.}X�j�|�C��YX(�I��p�8l�l�5��<��Ay�	ۅ0�>����$�������(0>��lk$
h_Ǌb?�bh��1�o�E��[J���yd�#2�XB"�����݃V���/�=��3����I���q�9p,��5v�!v�����>eo�Í$\�9	6����⁆�9��l��l���kj��B�ڑ3	�T���F���4���j��ȅW���N=��ٱ��U��2�z��NU�Y���Cf5p������Uk�`j��J6�X|����Ι]�G�ҏ���p�Y�/��q\�����ʃw7i��/�?�۫��������{I3�i'�aٝ�^�:	Tg��M=�����2���42Z�Q��p�&5�G�x��{̷�5w%�'n	kE
�(p��������y洃#Xu�'d�=,��?��)6��:,ˊj2t2C����2j;��Q��C}w(�S�ǥ�OX�BFPA<�(4)�({��k;�%�9}e�`�a%��� |Y��JŢӘz���sS�r��T�?uO�N<�Csg�m��줢�5l��srO�y��5/�?��ʍ�G@������	�N2��<d��9��a� �~��1E`�&6�VA�uK�<��&�ո�B*	�s(c��g&�Y	�BI��+n�ʠD�Ú� p����H<��%,pP�П�G�'�s�f^�gF����=�Mb��Y��V��x�V��G���/F��V�5E3R��xN�ԥ�H�劭i��7���2/�
�I��P� ��7$��pdiT�!�FL�M�!�����A6�Z�--��hsb촘��*���
!Va	?��I��x��W8"Y�X�bV�R�V���a�,vDe%��4�E�&��<(N���\<�OH�y�C�<-tO�"�]�,5��va�Cm��"+"��z�˗������=(�V��آ��2����J�AM��y�10�l�Џ�7NH]�t.�\a���=��}<���d>hD�JX��q4Q��9�P�� L%�)��H�[�B�$[z�gĩ�5ᲊ�r&h���'�F��qYg`��dLJW��@h)A�h�YV2���1��
m@����_n[�����t��$�<�#]��x���������s\�A'��n��H���J�8%|qZ5Y�S|�nx������b	��Dn%{3��.x�q��i�<>>ocq&3�.�>������e���ã����n� ʽ	��D����4���>���ۻ��,i��_�	fN� P���&d,Ǘ6t	��#�o�7U��;�0�I{�x���T����ʘO��P���tF��m�CT�
[b���ɹ����nm!rA�~�^����ʪ �!U�{�E��%�]e�i�y ��d���i��~Ȇ�F-"O��~�9|e]qx��7�{ ����HU�f�#�qo���Q.0 "�����E�`*vC�{A#�2���z����N<�����EMA⫙,Cy�or9B���+B�x�s0[�RO@��'J��}��g��Ke8���'��O�9�/�����3��I��.Gd�]��1����
o(��[1�Yi�HP+��L����?���w�(b�LH��.��}6��2�Vm�ˋ�ۍ"ӫ��13X|�e�'gl����ϗ�5�j-���-��5���܀����/أ�x^#������h��b��UAju�����v��Z��x��H����|�=V��� �6^��Z�� ����p%���J�Q������	�3tJX�0ح����
j�w��N����"ݤ`Wސk����;� ��� ,L�)''JV�45�����#v91�L�>8@�IޫfW.?b+����4"j��&n^U�
��Fz�3����	�Ps]�D/:�ʞ`)�򊝆�?�����/:�������*���u�J:pj�uۊ �O����E���I5��������4Ew���E�g��-������*�|�	�j�_���dؚ=ND������]f�ޔ�H�~�ۆI�Z?�w냓ƙ�%�0>jx���g�j#P"ڽsY���[$��>gV�e�L�
�\B�x���2��X��?P��5�h�k�\���Tt��x�Ms��������{���ǽ����䘸,�O���+��eG�)���8&k�VQa���tqX����-r�~��!�NHmzͿ$d_Q��`i�4��5��~�������72�!;�t`���)E�^1vJө�$]Fc۵�S���^�_��a�<�NfA"�e8��,B��B&��'�����ʱf�`��oغ-~�D*�/"qs{�2�C�5�A�o͇�#%��(H'Jb�[
	�'Ӣ:��U�t�+m�q0���h�ŗd�A#��ԉ�R���^�̷Sd�>S}�$��A�y���H`Z3��AFi
��V���T�?��K����t�X>s8���Q�p*P��1����M�7KH���޼�Z/��{	K�̆aQ�:��u�k��'��&9�_s����l������}���ј�c��$r��N��Z��]��͉����:�/����{��B��|���[��n������GǛ�����y�#1�K������>�i�d���z����t�Y6*�t ����U������ߘ&�{��]� �0�%�j
B# �����凟�\v=1������� �p��H7y<�n�Xa
�ND�ڂ��j�:~ݸ��Z^��ނ���J��g_�s��jc��@C���0������1t6�k�o�ڞ^�^3{��b!�����/�;���k�r��{���9����b���G���v;�F�y��Aq^�ھ�M����}�Y�����s��m�ֲ����}������Oo�;{����Eۓ�j`fƤ�wȳ��!���������a���d��^�^�Q❭U��ȩ0TC���oM��8���yeK��`�m�Ƞq@dV��� �a��C��������m����V�Tr�a�M{�U�um'��v쵝m���-�6ITIJi��a�k�����s��/vg 	������紱Hp03�̠7�|���憗k���YÍҵ*��R�*�������g^O�Mr��|3z�y�)`��	��n��_�w���)�?�������iZĸ�9% T>L����ɩn~�����b�i��UD=����V=�
E�a��_�+kY�D��N^C����~-N����5���;�w�>VD�e��)�@�x�1#e�
���W��EuC�Zc�j.8�E=N�9p��YT'�l���_su����t���#'o� ��vQ��Y�E��b������?~��� ��2��N�-�-Y�jʊ5^�Ƿ����(=NȂSq�0�`qհ�����_����q,a��G�0'��WԊ���(`%�D����~���4�`%O��Bʈ0|(�xյ���'�r}Q)'�"P+���P��� �ҬTTB&Q�za�t/� Po��K��Ȁg��5���Tդ�7vχ�prɫ��T�̫h�Z�"RV7]9xMg}�Q��	��+��D0A����O��!�L������DLе��/���B9���˳��)6k����N�d��sm��˞lc0���k/N*D?��y޼Xl��4xz���{`B�Od5��g�G?�n�l�=�	���|�+��2��� �-����&�n�Ŕn���0]J���ӑ�������������/�Uw����`�qH�#Q�L����p�u��W�T�x*t�D+}�؝��0�.A�x�3��f��+%�`�=�l�4����G-�5���첃&K�z�!����&K�mS�@-�(U	��{tɏv�I��L��M�!ƉSN��l�~D ����d�a�6A}[:1c����~���!����	��P����FJD)�������崒6`�V=�0�� �)�jz�T�-A @�Q�]坢�P���e�.fi7���>�zt`V��˹��x�u.Ŧ�WJ^�Yk�S�"��_	��ܤH��#u���M�D5Dj��?_o��<O�8��8���g����'�tE�m�jA ֜<jB�m�%څLG����b�R�~�q�T�T��v�P���d�=:��>�@��[��Tb�LX���A�!�%d$r5�+��p�,�Ϧ����duc�j��� 6TҁJ��}'cC�@89��x���+�|��5����4���nw2P��E��qw��E�UA;�Wr-�d[������Tvr/.�ٷS�	�KԏYr��H�YK�u�=��Pς��ꖵ[՞(��*|�&��� 
�Ѫ0n�Vl��1,�n��A�[)�h�V��ʦ�-�<�jT,+��[�k��W7=��"��r#���E��*����F�ȝtK+"�T19�9<�z�ų#�re����b���1�f(4�Hq��;�Vh�(���HzQ܈@��R8i�{�z��X���_X,teh1VQ|����^H���y�����<��WM�u���l=g<L���]'`v������������7{��n�a�A�+�[���H�6�:�����`3W�?�F��=�1���~�4��� �4E�/}� F�ɥ���%�������q��z`�Hv3��Ky�t0b����_쉶i�8�KJ�NZ娮b,�	K�q ���\<pŸ́d/�1�.�}B���F�mrgA���y�BFO�t�p�$���$,��D�,({���M�'}�LP�y2m�O{��4avي5^�֘8�͋/T����r�\<����+�ֹёr�뽎��������c���'t*MKQO�96�͙��B�f?��7_�r_�-g��-s�<@<i���Sn��2�� �NH�v��'[вf���d S������q�F��-����<9��랞S���9�F6��lw菧?�M<��ΧQ<�[��&O϶�-�T)&
���%m��7jQ�D_��Q=�DWP7�W��n�^{l����O�FP��k#L��h�.CD_���Tc�v��t��
J��Ng�M�z�Q �����ɅB�ˑSY8K0ٜV��'�AD�L�TI�������#��2>$�7���� �f�A�X�A��&ҧP�M/��t4�-��e�˵��шti����$�.G����i��Upͳ8�i�b�����\-�<�Tqe�He*���:%	BL�6 2�Б�v��QyQ�P^5Ti���a6�b�Q��"\R�z�W�co�i�������^N�p�	ǰ�M�ل�N��t\ �Yl�<+Z��H.�OQ�f�N���I��:&&A%����+�p1����`H�w��
�
��u�?R~���c[ϙ-.mZ՜�$q�C�7��i~~��U�m'�(���/���8%�����δ:!R���C�-�(%�؁xJ(�-�����~�h9Z2rFn_�L݌+��:l��n��G��c����Í<�S0|�0�$�����y�>Pe|Y:�Xj�m�q�ͰbIh��$([,�,>��U�y�dfN�]Q�ڠ[D�C*�K�@�!�kk�x�5&�^��ͬ ޶����i�bYS��*�<��%��`�l2Z�o��K�������S��Xі��B]�f5�;8�J��pk���!�~�E�����3D�*�[p����y��,p67T�Q��a~�H,t���sT�ϵG�.>$�uU&���-`S�s�s�aK��-��#����jHy�pތ/+��C�ǒ܏�����2�=�#�"�o�E*�&��ő�"(����LJ���L�{��iP��%c��SU'�iAj�Oji)����.ak�d�:��V��Tkx�h+�\��'�8-p��4ڶ|�]O��>t[��T������a1O����_W��(t�6璍�j�˹��b�m�m,%�\�G
��S9��ƕS�G/��9ݘ�7�呎�K:mӪ�tZx��I���J�����tEl��X���h�s�0�Y���N�H�"�^�a����hx��t�� <�ݫҿ�D���e	U�}[Oe@li���Jk�oE^k2޵��z��V�)0F��}Ps�L�t�z�y��5�)D�k2�������1Z�o��^�r�Hr��z��j�!>����I"����܉E<zÞ��ەs����b�|����[�i�@;`��-����e��4T��8J�=��I���@��%��5５��(��x%��{ k�R��s�o�#s��Fb��Ӌ�F/��*#s3h���?�9�x�WY���ű��8��$�I�y#��0�Ȣt��8�P�C?�P8l]gU��0���y8���+I�ea�*El\�57�����3�{O�b�SQĥ�cËz�=vA b
�M���?�_ �$2���^��`
���l�C6f`N�c�(}��4ݙ�)n_ �r��40m*��$�wdTe��'㭱$�T*^ܖ~)�j`�֒>�,/�K�l��*�l��L�W�Ͳw��{�-�ќ��	_-a�"J�/<��$˘�K@�����O }�#p���xo8N���V!����&`�Oܦ'\��^�>
���ʜ���B��F-��@����UGn�*պ��TP\AA=d��%�Gz3���+EzU��Z��;�:�|�]�y6��Ϳ�_����B��5UB�M�j�c�S�mA��B�D�&2K��ʑ4%r23u�d��g��f�<�Ů�eݙD�I�wɏ �*`
*|N]XI��	+팶XX�8��/^m���J8m��!�d3�}%܉�f�J[�EdGk�`�`�N^�<����𐚲���@Մ��u,�+o�Q>�t:f��0N���Y�MG=��%�]l49Z�=�Β��'���?�����jjޏ*�iP�|�����('3E�!�_�?C�f�ps�12]�+���)�R�a���ەLJ��Gt���n��"gj�s�3��,�IP�(>��ayt]�	wl���q�Hm����ýݣ�g�p�?]����9c���"��$��es3�T���{ďzΡ;��=���o�X
��ł�Y�*����aA���.��
�
8��� PXPr�y"�p�1 ���!�Pg�@��s�2�yG�弛� ��.�q�k�gG��������S�mM������Obu��c�2�F
�
����k gn������\���2���M��)�W� �wU����¹0F�\R�����s����ɩ��v����n��q��!����'�j��W��%�M.bʲ�V;9�8b�G���w� ��O�(��Q�b� ��v�cJP����0o	���ܛ�I\�@�j ��#o$�����f��f�P�
�4d����e B�jB�%�sH�L�v"��Aμ�3wŉHPXF���O�h*�}yL[�I«ν�a!0�cr�H�����[� /���:�s����gŢ��\Q+�f���*��E-�Ǫ�&��ۢ�}�;��w�eY�x�׽��H��lDo�d7�:m/g�9N�NU>ϱ賟+����-����m;+j;�{P�Y� ɷ�@t{�P�/�ᭊ~��'7�\E��������ޡ��6���]�xl����'.����b��� 4����q��Z�ʾ�^p�_޽b<���I��g�P�ޫ%��$U_�4�IC����>)V9��l�Va�&1�VYK�p�Ik����z��ɝ��	 :�Ɔ~$�����������LJ��^��l76���ݢ���P�^�܂2c�t�G�e��D�w�������\�[RY�]��Yy���\Y2�E�5�:������>�b?�Ҭ������K(���dޕ������eyoJ�����K�\���������;)�W���^����h���Q*9FV��1DI�->C�"�Eg�_^ņA��p���Y���K�䬼�(�_+�:y��~�{�z�h�Ջ�jf$L��L�1i�Ҷ�_�T%���̞�z
Ez>����[�[4�z#������������m��E*tX�г.f>�n�O9����5։�0�Y����{�^��[]���[�>����d����MqrpjB���5E�������	�����
�������p�1@M�E���&�(�c!�"��4�\��a�<9��b�7$c%��L����m����fe1踱����KnX��7�D�殼�[��Rk�RG����:g����FODZ��#>�
�1�q;�r����,�Wb`aEمL�\�<á&j�-����^���&Sm����(������G�7>^�wQp��|�,�OI�?N��0��F��_7���ǟ,��]����0��hA������?����?^��]����`���Nʫ�4Ps��90abw Z��08w�]�BN����e���q��¬�ռW
*f�I��|k���,}t:v솑Gqb��� A_������R���)&�"�����2�6	ӭJ��+*�P�7Tm;7�I'r��ٷW|^ƽaL�
��
ޏ��[enM|Օל����<��I�s�kh8���d�O3��6%d5oP��m�����\�^�9����v�g��e06���������t=��`H���4����0�l�_x!9�a��
����f�J�-��-���/���d�BO��3�<���iD��w�i^m��5�T�N�W>��3���t�e�$%��L �x��.�t��X�Ӕ��ﵣŜ���O�<�[�76>4����������+�s�9w�+G޶���UВ��Q�b|�V?g?�؃�qd�.L�� h��W���:zyv��lKx�"���3�f��t8�o��l'y7�tI��%Y5�5�䦟�1����G?�#7b���G�ӟ�Ch��)��^c�6T��볉U@�]��s�����=��g�V��lb]١F/�µQ'R��{r���4؍)۬׺=�غs��~<�n�T�B�~�%�t揼`��=?�>�=�J?�l�K�-�����W�s�����"z�i�B,�
o�z�1��	Զ&S:��(	ۀ�ͽ�z3o��`��]�����R��#/g���(��6�?�(k������<;�~~�%�3���������<���z���_��}�Z��u��d�������F�+�x�^�5�{f]a����do�-w0��G��t,��q�/�9�qp���9��^G���{��b�t�^��~0��	�y���
 f������#�F~��3���>(�hj�� f��6;�F�����0Y �A��M��|C��@<Xa&��$!�]�B�ۈ�G� -HS�zṠ�z����wvu��_7�MB�?��
�>�Ȭp���:�員)���c!���x:������{Ǔ�N�i��ڊ�>�	 �c/�L\��鸃�;�{��;����ܸ�S���	��|��X�������]��1����O�ᠳ��>�!�cpF:F��C3vY��o�0�߃��p<�Z��@}7�R�o8_�m��ϯ�c����[�z2��V� �D9�qDK���\��8Y�P"�Y�s�6�؅���>��LU��߻h�Q����&.�8�#dGEPu0�u:2q�hz��`��x� �W@�d����Q���6����)��l�Y�GW�p�F� /֚��:����I���=M�3h᫓��޳�/v���^^��3�q���6��Kڗ�I��Ir��?�S�/wO�`�*�D��0 �\����bZ��3L��>�6���lo�lo�w��2�+&X+b��>܀�*���k�����BY�E�R���5A�)�tG��.m6�W�?b� ػf(�x��3fE)	c�?�����Nc���9��1C�8s�#8��V�CM}dȂ�f�a�E�ek�o1}?��
��K$�#7 ���W���j]�����X��z7򣈌��G�O�y#�#����qM���wI�b� ̭h�=���p��_��f�Q[�m�-�����/�g��F�H^w�����a#�/�F�m�lf^�jb�Ieޞ��.���1�u�(�CD�&J_�8	��"	3�NG(�@*U��/S>���>��@Å~ɥ�����,B^m(�}���O�Z8��"��OD#�HR&o��kʃ��s��ͯ�0��֡�x��Г+2�ͿFؐ@~D)�!}�>�[�GP,FB�9��>Pi�S�u����ד׃�U�u��F��ZoXMSc?��������/��ON�[8�V��>3��2h(f�Ŵ�$� ��g����W cW���_-i�G����u+ k�u���S��s�^�|[ a��e]�e���Z� �(���й�@k
d�N����I���vEa�[���\�(��[����ν�{��;���S�����>��	耤"��A*q�cmU������ !�}�s����e|�p�2�U���Jy�*E���!�2MEp��+�.�1��S��vQ�R���=X(Z�5��?G��M��6�.��r�a��F�pe���UW�؁�a��@��?��A�|�/��K�h~�h�I���٦s�s�N濵o��z�������̏`a��o�^O!j���Y�e`�r��!>��w5<<B$ݠo���F���4���j|Y�h����Ɯw���7�r����h�sL�a��}G�A��e5������r
�� ����l���/���M�e�1\sł	.�&X�A����6�{3�d���&AX6�Y;�d]T�=����@���rC��˦I�y����㓽���������J�i�w����/�$^�U�����u��� dJ�G?"�"�P���!�y������������y��+��F��ʲ,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,˲,��U�{f�| @ 