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
�      �;itřNB����G�/���yn��-Kc[`�F��E#�����g���=:�@�f�a�삍��l �^�`��.qH��a�9br���~_U�3#ˀp���h�����*颦���O�Ğ<s�otNC���|�E���Hc$����#�H�'ǒ�5�W	����aI�n���Kݲ��(9��o���ا�?&O���T�LeA�y�ĝ������7�����Ԑ?������U�I�Zֳ��m�������%�oԳ�����%�I+*IK9�H2��o&)�C��&}�KAHP\O"����YQ�o��*L���Q�*�[���`����R�SU�	:,�$J_���\���|�q�x�p.D����k�5��p�PJ�E�!�4��3D<�*���6�?G\�!aJh�o���`�Gc����1���?O�$�bJ$�jzJRB�V�sH��L�X*'��T1#�G�u�'%_�5��z-Iiz��Qt"dy�����ȧ��}N��g�"9^p`S� ��%���>/ʺ�aH�t�2�T]�9tR��d��Ռ`��A?3��?��Rg�S ����[������+� 	�PD}�~�f�RE���$�F�=�0 �*i!6�|�ZM)���ҵbɒ ���sId�1VD���s>GE���a��Ɖ�?@L��s^�k��e}&� ѤQQI�����@)�@eP
�=Ʋ�f�mp ��J$��$F�$�\8���D���R����d�3�7؀>
��\N|� �^N�}�!?�m�S�F���Y'xf;�>.�:D��&_��m�
#>K� )e�����9�b�)pS��D3J�a�S���_*��;�'��a�<���1`����`ЊZ��+Sت1�f.h��Pk�:�����Ѷ�����dm-�4�HԲ_��e*M$|}k��k�����Q�C(x��1���d���i��|�c�ڑg9��ř�o/���+Dȉ�\,T6u�k�~�M��e�7��Uo'�OV�6��)�7����Տe�F��
t',�b.VHw�R
b��8��n����	�B0�:K�i�y.pd�f�4$%�%Y�e����ߢdI���b�v�sId"�KhQUiG�c(�"d������"�*�xl�8j5C�C�4�X�X���k��7��v~���t�n�>��
�t���'�ദC��(i�*n����f��
�rg3��G����_����wu�;6�KW|Ւή8�����_�RTD`,��0�(N; �(�aR��D1;�*bː�X�� 5��8���yVub�L�dc�߹&l�RmN�Gr�@-IcI+���T�4�&��|��N{���E�2�0����E��� �pnO��U��iQ�}RK�h]x�,�,>e�� A�Y"N�R7d�M[��Ҟ)2-�M��0��-O�p��$��R���ؘ6<zM�E\�R̥�b2=�hm�s�O�EcwOH�*M�e'?�=U��\a:������%�C�0�?� ]
I�:O�x�jUi 4�T���v�ǰ��|��U)4���������.d���s���l�t�Ш��rpܻ�5��.
>����0QGo&�g;�w�L8�1E�"J��(�b���4�9�r�]Y�umMj1�����:��Q�]j.P}Y\5Cs]������Q�R��I$jJ?�v�H�a�Y�(H��Dj���,vg�Z��i�!5��U:�)n$�t���b��d���d���95P�a�;�*�?�bY�AsR�Ȭ�e(�b�1dDc�M��&6]���=ۏ�SG����7S��hm|ܺ�7K���h�A}�=��h#��ҵ,p8��5�I�yM'p�<�=ߜdY8�J|8�wG\g|����ޠ�������ʧ��/�SGc��9sJ���|z�wL�����<��/�mk��<��Vt��x�؏�e]�Z�����xǂ���[�t�	�5G9�a�@�)q0,s9z�(�s:M\O��y<��D�@��2�Bq�W���Z� ����9�	 ��!#;`\�hڮ��ѥ�H#��D��S
��k��'�((�P�+�J��KX��i�l�7Y�eW�V��I�w����`fp.C6���*�h�sӴ�IKДҁ��*� ̋*trS�c���X]��ol�~�����\��E�m�������2��x�~pЂ���a�J��Y����:��z3�����hҢ���uG���&�r�T�a\&�02	%Y�s:mx��-(*�s�#}���C� �����y������Ա2���qA|QgWrI�J�"�x�7����jo��b��`&�&QL5�kV�Sm��aڡ��F#��@�����y)����>�	���$R�Bߚ��ڦ�`@(%�u�c2�&&�L�M(�|[0���(9�UV��q�xV-në,��˻["v2��9ׅ�Æ�%��l��b�PuN�]�u%�_(+�;��2x��M����7/�8?[�!im-�*�d�M���$V��4ԑl.g�b�ԣ;Y2��_X� �⇀<5c�$����\�PJ㜟�R�;��,��1�!�4��B�!V��E@D$8zzA!�*w�0���3�R t-��F'B�H8���s��(<�����~���2��΋ZPօ���8r��E���J�Ccç��X<��_M����OJR����U!+�����~��e����`	�,����Ԯ@�u$��mK���.�L���E(���9l���6�爨Yq�9��sMYq�����/�M����@�=7�l�$���x��� ����qZ�l�eD�9ѹ1:h܁a��� ?��y�*Q${w��"Ҫx���1|�=�y^�cl�3��I���؀6��6D��k��d���ֹ?�� ��6�`���Äc�O�k�L�+��Χ�����2/��5"s�N�����z�+SE�n 7�����1`9�~�o��0��2;KG�Y>�C{��yTP��-�%�4��X(jd}^(�X6"LP	?��$� ���c\����.URȮ$_� ]f����8٪Drx^��ky�ʨ@�;,
�e��q�D��w����U��
�|ˆ�Cp��B�6H��V
hE>灼�:	��l�1Z�_\�b����R��Q�}ݱm=��=�Vt��a	�s3��G���7m��Cq)bК��4A�
��wq|9nS J 6�� �Q|=�mݽȗ��{
9О5LB�j����@��r`�_M�aޔNU�Rc>+�*�q�;k|�Z�/�	F�����D�?ϗ�00�0<�����DK"lV����y�"�u��XP C��{9�+�U��%�E���t�(z�� ��w�����@\
�l�3�{Vt�y��˖��K�<ԯ ��i3��A�n������c�1&��S!�A�c�[�Rt�u%U;ƒj�r�m�TQSPˉ���*R
���E��L� ��h$��Y�tE��]�[ 0�!��;$��G<�>Q
g�
�yJNJLy�al���eK�-!d�=+B�N��� f�����Ӊzk��I���^G��349v�,�`aP[��B.`ۄ:Њy�d��4��Aa�����c^h�UǗ2�i2���"�2���!�|+�]QU)#�Fd1Ov}_����(*$$��2�^�.f�����Ӡz%J��s@A���h �d`xt<@`��p^�bV!�B�b���֐Lӫf�Da2��a�� ].7p���(À_E��XP�̨���p������Z�Qq��u�GA���
����@�
�ݥtmR���g��u�T�N+I0����-� ���BO`���p�n�G?4�t���ؔ��ʐl���n���9�'�I/DqjIHI"|��"�P&�9OL08H�Jlw����<��r�� �S��!�Z	% �b3�� �B �;A� �ߒ�J4���"�;UĽ��3�����^	�`���xQ��[���Dyk�s��5�P8�\�־����C"T��r;6%7�!�lr~���)�8�Z	Ks�h�R>�V�<TTF��"���CL�����'8b���N�9�A;��)8�;*�-�Y#!e���}���I��kukÔT+2�E��xZ��R���.��ֶ�ǵll��Y��q���xO�xW�b0^����d��U��M�����7v|f�A�`�e�u����H�$�ѐI�U	���]��R�.��,���J��LV�A~���r�L�����!%�_]��jW���oZ��&�(�~l�t���<X y��`��x!����ZP�%��������Qn�uveKG_(��W�uV�8䴆sJ�?�=V�>繐�n�YG������M�x�N;�XFZ��al,1����FbsK>@"V�t��M�4%��IH�A����>?ԵȒ�nA��E��$h�t�U�m-�.�&�Zu�{�eC% ӿ����~���A+�W��<�1��� f�b����U��	IM�/��?�ư��1p��Saq-�`��4a�l2���b0���C5O�=�g�7Od��{��/v��ppˡ�O���Mw^N4����˶�����$���޴����[�6�>�x����[�歹?�xmz�+�z���l�ޕ��6<�al��7������4| �nۻ��ܵw��pσ/o�U���ܸh��_[��/>���ww��ug>}��C���Ы��[¯|~�|���/�������ץ~ھ���C5땻��樰���[o߸h�C3ιf���f�o����O�p�I����Yo?��v�؝��o��=�z�W�=s�WOY��w3�k�vk�k�];�������K~��t�KΊ�|�Wo~��q߭��G��9븛[�����m3��u���W�u��g�;c��W������h���Xu��
y_f��jN���g�=�=��{�<���ᗏ���?=`l[[����T}�̧�����e�~�������>�|��Ɵ�v�lۿ��g�n[y����}����?qʚ���G������w�i���y�-�^t�m;/�����é����)?^q�ߟ~�)�U������sU�z��9�KO����=����B�Mׯ�������N$�e��a9s�o~��%�6?'����=�F���v�wǺ;��ߘdթ��+����nڱ��G_���o�U�[7wR�˫��z�'���/�6����yN�����_O&����j�����:ug���7��ⵛ��͸sur��mk.�=�ĥ_]�u���N��sms<�I�����_=~m{��ko}1���k�}�'�������~���3��ˇ��~���BۯW�G�\�c��[��pS]�a��=o�pNC���T���+�g��N����`�\�U-t>����9�^���?<�?���i��w^�T��wθ��g���M/���K^���e�ȕ���7m����w�޸��n��=O]��g����'�ۢ���F������4�����W���q��;�a �Ni���$d�%%���T���MJ�4C#�t;0��Y�s�}�w�u��������W3���!g�7�[Ic���b�b����v&w�dNd:$��(�s���V��3�?\���z(2��>��_ �(��K[ݍ@����۟��)���1�|$���f���MaE�%W�i�-]9���w�#vj�N�j
�T�9��,�Z�s�d�K0�/�׶]#Ѽ���Z�A���vÉY�Dj`<����K�B��B��
_�c�~��t�@G�^.�h�+�|L����&E��M�D�iD��ǽt��z9;��\E�����C%lɊ��+�`O������L��빓J"����d�
���ҿ��Л���uW�%�([%ceM��p���s;��`��eIyQ>�m���%������m[��#��c��d+\v��]�ER\2\��"��^뛗���)@�CiA����(��l|d�~?��L��fJ?=�/�F"r.���h�H��A���Ɨ�d` ׾�z��٣��	���*@�r·�܌��P��q�����C\���d�IΧ���]�W6 H����)����@F���5"��3b["���S-��ۋ�O�Vl�3��WG0��Q��ά���[pέ��l�Ae�DKwg5�*mp��a���-w4`:Jgu��.9���r�0�� 32�:	9��>V��J�r�����R����ݕ�Nn��EYBC-����TJn��_���Սu��a�9u�����Vv���O�:/&?�K�XN�1i6�i�(�
ފA�²<�A=�_Y�nl�ɰT�~@�F�|�t~�T��[�$�0%�ͮ7��熎,X��L6O[H4`�K�WW��@�z�ه�Qu>�3=5�_x1~�Һ�8��6�0�\�Qύ܆���߲,ۇ������{��%o��K�A�_��ΪB�J�i�8�kߧg	�)j���d��}_�VWkO�$A/%�t���__��2۩�:W�����\1tb��6�KԪ���t�CR1!A�NEƖ���5tm��OD���MW/]��a����kVއOB6��-#���-�u��v���݃��7K��5O��?�Y�̮��*�2�6l�~���Чkhy�#=�tx��J���&|JqvH��!�kz��]!�=9�������|��0���A�(��1���8����l`�uD�����OD�ã�ao�?���$�^�r�7�ٙ� ҫ����y��M�-�����;-��� �T��jt�B��I�cxa7'��]��1!����`	��D�/B�#�.����B�t�Q�UA�5)�0x:�8x�~f��$놢���@��I�,
WUSd�-�9ڸ���1@rn�:��>�PB���PZ�i,�9��eK)���޺#r�o����یF�./ڼ���}������~�]��8�cl����]���t0R�ȥ>�u�]���sl6P&ݕɻgԨ�o@�m �z�x�C^
�Z�БW��v�\���<����_���{��0>�Ѡ�=��SS	�����Y���J��uˤ���U7�F��ЮY��덓r뉸��PԤ����A����%n���ΫN�eƛsb'\�h�@)/���!Ж���T����a4���mC�S�n���W�ޕ�����Ìx����ɪj��X�����@6��w���z�������\�[�����}~�ʤ��������U�KĤ|�vr;,U�5�P+G ~&4í楍������c.�kGM���>:r�H��B�Չ�e}���S�����߹D�����Hg@����4�\@�3��L� �!��B�;�3�%� 2��)9E[�%��yO��M��+�C�wa��t%�.�-	����x�I�.%���P���֗]��-��'�e�d��
�š{���\$w��7e_�-H���m�E�8��z��LaN?��C��tm5�/֩�E4Į���qE�h�ש��}�'�tJ��[�v��VrH@+Y�:��<�t�Z'��O�f����X��lã9�Ejt���:~g�s���aG_�Ka^a�@xJ.]~h�*�_`�0%6|1����11�X]���+�V@{&�ߠ/j���]W�o�L�A�j���r�y͍�d3��Z)i+l5I��
m�x@��-�W�I3[���te,h�������2wg��P���D�s-�i�':g���>8�O��8G$�.WX�fy�ȹ��)�Ed� �Y����H�"��
�7��� �gF+�d�t�
y6E�C$�Y$��fqȳ�P��VK��`I9b��i��1���FQ;��>���Fa؝㘽*�� N��z �'4��E�nr�G�J�U��F����yFgK�����E۞*L�z���:�kOq�Y����R��6F@s͎��g�ѓb߯{�!�&��Z�.�%B��-��-� �~R&�z$i���,҈�K]�ϲ�*���(A05&3���R�$Y�:����X�?�!��ʖ�e��V!8��/q�q�i���~��4�ʦ�iDL����wD�Œ
(��-�K�P�,�`�F3�r���O��)���h��Zž����m�w��3�Ng<S�	�i��S��!��*,�� ���'3������m O�1>�_�-�0�	p���j���K/!�m�1���3*	#��w�E�M;`P��F͇��Ϝ�LnW�򮳓�a��+���>���]���?�/���%*.&y��K���{�u���׽���_�������{�u���׽���_�������{�u���׽�����%M�	|���b.�i±i%Q��Y���:���*��Zx<YwY�ٹ�����o��;5wRɁ��w��0�[ h�Xp\� �����uj�Q�6��i$�Ws��C�% ��<��ϜI��iu�?XN �Z_����b��_u��R-��!t�oџ'Mn��_�u�h���8
1oAv�|�;h���8�j��BVi��n�@�!�˼��+zm �%�K�n��/|�뤰}��Sie̿{1�e����n��a��xr�Y�{!�7 ���1���;u?/�� ��I�2�.6�l/,����>�T�]-��g��Q�e����/��6A�MH.&� B�:i�|;��[@'���[����ct}\��@���5�n[U�Y�_�%� <�kt��3Ob�;^�v��
�`�Ԇ&0p��F���w�������?�
7nb��G��2o�t��4��'m	eṲW�N;;f�ϝ���\�"�"�������(�ɤ��Qa� ��@n>�J6&.�Q)S����}k,#���Th�TY�w��'��^Ы0��^�zRǫ�5!V��L���5��m򘨮�m&�������21s�� e���8i�t�\���<�>�ś��z�d�3���P��aȋ��n�+6&i�=���X�;x񻧅���|���v
m�	�ߦ>��lM�C�����41�p��?�7�@��gL�K0�_lo,��^��h���n�W�V�3�ڦ�h��2�+B���xd�k���S�O�#��z� ���g)��ۚ��u�ˢ�Ⱦ�0g�aW!߷!�vuA/hӦw��4^5�>wnqyx{�Qo�盶R�V��Ce�-]�����H0gAi5U��c^��v������I���L]�ֱ��ݰ�)�d����?�E�ۻ4����+��r�J�`sz�_�]8x�l���ͨJT� ���R���ߍ;�m���@���X��Y��uW:�v��v��y]�y5N�����:����15�ˢ��30����\��j�LA�p^.Y���a��]E�DݢeH�/ռ?}+J��{Xܦ�S몌�p�E��B�\٪/U�f��Gԭ���-b`K����}O���}��b ������с�����8��$����N�����4�ȗ�N�����%��C
�=o�tuZ�$c�ݏ�>�΄�d�]/�JY��4�����}�#g���L��1�A_RO/�k�[�]6xe�vRUp�]�\f}f�L�����XV7_�y��K��i��:�����8/-8&����p����g|>{JQ��~�vv�^l�`�� 7l�R8��k�7܌N��ͧ54�c��������M$���/��ZwF���m��_�!`Ӄ��w�R�x�C^X�ع˧( ����K7JI7J.]H� H�J	�K
���-�J�t�t��%.�w�������;s_���<����7��I|��� ���3��j��)fL�0�y�#���e��*����Ԅy�b�A�+��၂X�`����k-��/J��ζ���@ڬY6}�� �Hl2�SMC���i�W� �<����~b^�?F�
��h�Ū�Q��2���YS\� ���51 �K-�h%�������,�_����b����xvy�s��.M[��;�p%hz�\R�c�eH.E�*���|�[	��g-|��g�ڥleY�1&?��M���H���L�;t�Gg���褌F�q�AQ�Y�7�j6����ӿp�!9��i��Vts��^�`g۩��tX�A��CYw�
��a���~�N-f��2���,��<�`ѕ��P�A���U���5F��N_�v}no��������o�Fb��K���GdQ֢���u����|�؞����^��/�JP��3-�|��|�OP)�t�����1S���fg=�%�����'�L�D�Y���M��
�
\�e�v��BT6����?X�#E��L���
0�~�6�<K���1�����׵ ��}n�|x�A�.�w%���$�agW�d8��E>צ�D��%�S3'�)��?2	��"���3�+�l��݊9�ٺB^O��C��Ů�-ާ��� �� /������0�����X2}�� ��V</'�p$��f�=�jQ�7-���l��#dU,f�����ռ\p����zX���D���_���%�Y�*3��֣��u��<���m�ך �?GmY%� Ќ@:9Qq��c��~~(��K��δV�p��O"m�?g}�U;�w�Pj�� n/�'�6	�s��0q���)m�ƖEpi���}������hi
S&���v� ��	eD.j=��C:L��� i�H��cin����&�&9@��B?*z�2A��`j)9w@�ot������6�pLM� L`1��((N�kk�)/��Toy��&��#;�lZ\�݇[4K�7��{��D(y��t{�v����)� ���!���[X�xpe��x��z=?P�"'�Q1�|.hݾޤl�� .E��[q9��y�r�)�OfK���QroI�8�mHb��z�烌5L�jKU��O��y$3I�����w����� �����§ 4�B액��`��Ǧ��DQ���j���a��١A3��!}G�斍3��*����6N��a#���������n_v��@�
ɣ, m��B���B�(Д�!e�J���*+kH�g#�}H��J�HU-����aM�ɉ��$��jn}�d6�~c��q�'4�=XG��.Y��z-+Lf���i����B=�O�U��Q5���B�^���K�a¨$M0D�YdK��w%9���`�q=�j|��#�Z��%���r�X�Jm��x�	���1�J02$)/���/�@���%�s�̣��q��j�F�v�F'm|�5�0-%K��s���N�V�!0W�o1��p���d�7��׌M��m��L#:ƋX�r�I���YQqN.��ф��U�#F07_��Zի6{s��~V�g�0Y8tl_[�I*���]���k����rh+mE�Rb���F'lV����W;���z���D���$����W�S�w�6�.+9j���հҪOe�""^h���P~�c @�?��멱��2U��;�4�)�ق7��UKd�e�w����7l�<���ɝ?���u/BŴz��{y~ ��w1��`q{��xj��zE%�����������Z�?���j�2G�3{Q�2�G��(`����`�O��j����9���s�[��^�cє�?�+v�X��uhg�nX�����g� r��1T1jŻ��-3Z�k��R���ޥ��7p�E�#g���ۄ����u�sޕbx�VD�>\��pqF��"����2ƺ"#���&!����`��k,��2f��t�+~=,�6$1�^L]�����ISR�]��zM1+�!�A��)��P���q�6��>_
��#��V��⵩��`qB���c��(�jbKq<��������Ǯ0ڞ:���=���Y���d����g�=r���,B&��%��ۍ�����g�uk���S��'߼����E_�^���$TS2Z�;���w�$Nʔ��k��(��+Z�0:���ތ�+̀�̍�^�Pb�z�ԖՏ+$/6R8�]�.��.��!>�mL��g��oO�w���ق��o�����E��rc����'�?��u"DO�߲�����%?�*��\��B�)�}�Y6lm�2G�V���!������ŵC���@�q��o)M>�����+]�Ё}\q����>8�;���~%���S�?/*��m��T�'���
����
(�ӯ`��f�x����/IȎ�o����Ϫ~��䓚C�e
ǁ�<q�M��F�f=���[R�C��.@&�l�e�㩭nP����r؞����(� ��g4��6��2�}l��M��`���zw �������W���O�����_T��?�;���;�w����ߝ���w�������;�w����ߝ���w�������;�w����ߝ����k�G;�6�46r��Ta��x6��aRm�R��s{R���!(B��˞S����*�t[���Cu�;��\֠�������7���֭R�2h럲3�p�PKVحA��W�E�N�sMMb^��L�a=����N�X��dMg��>�0)�L���`�b.��F��;�7x�a�c{�3_M�~��G�r jw�lZ��3Y����A��#��/�@$D2Y�YY��T��c{��Т�s���b�mgJĒ��8��X�D)�kڶH0��G�iq�n^$��@�Rj:�W�8�����錝(<�%#!�N�|�"-�c��r�P�՜>�RX<4a��L�3�S�'P����۔�VG�qc�7��1�T��'��qo\�f1CS��׷K��W����y%�y��/���[��M��X	���5�^���G☛�g�|�}�� ����n�<_�P[.z�_��3\�_���$X�c�˅]F��6�A���l|2��51��������{s�	8�ۗ���
��j*g�� r	�*�.z��%��%/���च�p&�/X��p���a!|�Y�W�K[)1��CnA�A~�m12ڧMh�bc�60�{|Cȑk�~��,j(Ɔ�����5�V�@B�*iuj7>�]a��aO�Som_a�U�J{����'�������\E͸�<��,�i�5*��H�A��~�l��VL��[�ZUA�w�����'U �#lg����݆Z�N���ȴH6P*�P2*)M��,HKq���w�8lS��)�NTdT�~ū��ſ.�xL����4�=�7��������ڄ[��
�l���ջ�ͻt��O�B�V��pN�И�MKA6令���d�q�Q�7�$Sڝ�i��d?(T��cF��Fjt8Q�rt���e���(Hө]���Zx7'O1�%����9���k�w(���k�dW!��dE<Y]�2oz�k��eDE+[<x���}$�cg�O�J�����xt�[{�%&�.!�\	c���ns����5���F�� J����Oga��u��y�~�y��ɉ[��(~�ڥ��IĆ�?Ku�hq_����ڣ��"���O9��Lg�L�*�A�c�^f�>i����K	�?���l��f��[�x��(q�Ȍ��mݤE0v!�Ő�%"�
*�uR�j��
S�|TqR�M'�]e��4�)�o���$w'�4m���Su	P����k��S�/ļ�db��~
$�h�#�^~��n/OY�'ũ��d]�v�yГF��Xe�
-���S;,׸B�A
��	�O�����{7	π���
�MI����Y�u_+�i��d�I�a �j~���G\���zz�HLe4�o�w@j����e�Ј�,K��:�D/�N��u´�h5R^)1���<��틿�u�W�����ԍ���.�C�o�s���l�'���G��c���nQψ#�Bv�z��[��~�����4�4��������Y2q�[��H;��Ta��9��r:qn�<��RK���}�R��k�L��H�8���&ʬ �
4�$� #w�SE�1��@�(�ܗ2� �r���FPD�@�d9eO.��& �3�n��[�ӿT%��~�����$U��W�8���D�u=�4�eIy'*&Lj�7Xt2��L��#Q�ȶ��Zт7+�p����r/a�kO���2�d"}�� D��~[q��'2�7�CG���P�����J�K�V,���ຌcGd�n1��/�G������7d �`L�G4z���c�
i�����]	������wf~�&�WH��mmJKHƨ�����M�K���")S\�_�z5C��Y�=0p� �'�|m/r��[7>�d��t��o�h�-��_�o�!C�)��b���ӣ���֏�]�=�v�8)v��qǦ�&����i�=S"i7�j��#�p��SL{<Ӳm���qE�9�5����	�*;>�"U��j��?��{�7WIU-�"Ұ:.�w�V�	��?�vv7?����M��C�<b�M�MnPc�l��gک2{5���u�8�]����78�w���p,�S�����P�G��I�J��6��*���b���5�~�lV(W˥���)�3)aoS�Xe�#�	xĦ����S�K�N��Z���|{o\�bM+߯�+4�:0��9�*=��e�O��Z�F��o!�%�Sd��ښ�(uۤO�)*�]�a�{������0Ƭ����1����m���QF0\ƕ�69'ɫC��}&˻Z���eh능�G�1���B����c%JJJ�S'(x���d+Y���F�|�)��z�ԨS��c����M"k���N3�
���&��WqǴ('�.r�x��[7�3x*x�y���t��c���҃�	C/4�yzL5�T�#*m�7���b��^MJM$�N�t6^��p�b�����Gr�¬r;Ѣ&-�=�:!m��c�HƕJ];9Wik1ub��0�4`9�g�����5�U���yQ���⎯�-�{��c�Ԋ�����e�����W��N�.��Iu�}'*ؕ�#"sqg�s���Z��t���s�9r|�H�&�0���S����gƶ��`��L�cU�-Q�o:d[�8Q�Vo�����>h?]�>M)���T
�/����;<}���}�}��<��Xb�/�D�٨֨���8���Uf�3n��!-�;�I̹�?�u��ːl���&��$���Ō�2&-�?�Yu�}�x�{����_J{D-M�Ⱦ常m�������G�K�z�ET�V(����8��֘�
�Je��_��~e�*o�.',����Ԋ_ÍN(>�N�|� S�C���u��պ]&���[4���0�rI���*W�jhP]k�FBMߣ|SsD�(Ic}����.]��� 6�:��ynX��)����8_bx1|�n����bbQK�X��1��*��hl���������Y?�5\5<�9��̾�e%1�R��Q�|��s�}L��s7D�q�w-/�wӈ"۠_�N��d>y ��}�$+I��*/�隳�p"��r��-��vW�������H���IĽ"��ۑN�)I���5��E&���ߐ�h\+���i2a����(v؅[	�^]D�I�^Tw
�+ﶎ�4��ޯu�i��`G7A�O�`AG[�_�Rh���������C���'��V"�ZC�]LP�����-/|�6��T;�e��'��`�n�:�z���(䜗�S�|�w �U_���Br�-�l�����wT�L��?��.Y�W 5�!��}[���=C@F�\=�nO��[��y�u2������	������#��8=>��zS��W��{���>��,�|�s|��7����/U����
�_�n 
� �� ?/����Z���j���g�Q��>�Q���g	`�8H�R��z� ��!w�gў�θ*je�LƝF�U3�
�E���:W"՟�;_ҙH���]�'̂m��؅�g��Ȉ�D<�CG�ϫo�� 'JN@�/��r��j�$��6�:�R��0��]����)�\4�yob E������,~Q�A�(4`?�JX��g���_>#r�u^��wJ�?
�8(좠��1(�⠸��̮Zr&�gR���n4��� қH�����8��; ,�w}�[(���o�*����9Wl�j�}. �U܋�n��ϖ���/%�ZZ�f���Ώ�m�f^�� ��h��vr�5�8M<�ph`Ώ�8nt �m-8''<�t4�����p�t�@�s�Cs��^� np�0�IA�Gp���8��,}Q�������asf0�㋋���@e&5�B�{�쬦�)�(��DE���/��匢���`�x*g��T�ba���C�	^4����r�`��2('�# ă��`5�0���ZC"�G����i`>̇� i�.�����                              ���H�Ch �  