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
�      �<�V9�s��PB���� $0f�'�Yp69|}[ƽ��=��@f��ٳ�{��0/�U%�[�gC�0��á�RU�T*�JR�C�����}�Ԁ�������zC��]����h4ۭ��w�f������;��4B�g�;{̯��nQ���F�z�8�&Zp��o����AR���|{Z��~�x�=5wQ���h�����Z�;ָ��������I��q�v0*}8�ywpҳ^�t;K�����^�Yz>:c��-���^�1g�N�����5��G܅2Y��ՆlI���a��G+�F�I0��Л��'ez턬I/CG<�+PTמΌ��r�Pٔ�bJ�6[�p�K�8Q��s9���ӻA�D�R���a�������ԁcFt��o��ֲ�c�q�?Dz���l���A8p���vI���2�7;�<�_�k�*9n��k��M�0�*��
a��aF	Yd� 2�J�'�AC���@� ����F��UUa��m?�n()\�N���H���qib;��?l��U/�M���r�'�V����T84����o�g��2q斫D�q�),��3�eM�sSu ��Y�5D>��*�7���s����* r���B���Vg����R�6��R�Lү2ETO�$ࡱ�F��o���2�(��l��"�ˉ>��&H��� ����e�ղ�[��->;km	P�\ ږ����j�d
�3��x���fUo�]�2يz�~m��Q���@�h#��w1��d
lL�ňZRei�Ż�L���TS�&�_F�=��~��t�c݉5�r"��hJ��̈1���s:4W�q%��h�]Ԁ��r���Y��+Ʃ]�m��o��+�r^�yygg�k�̈���8������,M�������G���jN�d�a>0���&�e�zF��f<�/��c�1���4��HiR��}b�gį�ǈEO�V�q=�,N����G�$`W#V'b�Ź�c�;o	D�u4���m�k)��IUw�ͭ.0�&f�6�C�uȍ0���~1����k۲���b&��5�ڝ��D̯G
6�(6m��)�?s��\���D�դ<�R�d�$�M��9O�w)z����^�C��x�|*P��&�H�'�Hp��i?�&�D/��n~�r6�#�Uv~�dB�������~�u��{��a����aT^�?$���� �<	V�)lhΩ` ����&�t ��f��H���@���Exi���^'z��'KlS�TI���ݸ%PaC�"CoJ� e��:1���1��wz���b�e2�0���p�B>3 .�=���b��<�+�Fr�ޕ��˨Y�@�WY]���hYz��
XM�Qͱk/9쏽�Ǎ����m��@�We��X���C���$-*�z��v�����D�5/�|�M�z�J��A����ɏ�'�Ɩ+a����,i]����!�ءͮ쀤Bk�4f����l��hr�׺���4 �P��������M�?�z#(C�U���d	HT���-1�y���TTbબ	)�[Y���u�^��q����י������q�Q�{ e!�q!u�:H��׉��XO�yJ�ڂ���8���)�������Ξ��U?\:�k�YA�ƞ7�oe�"vW:RJ��v��O,�V:3�Dnh�3����B(e�,>��>]i	'�q�g�T�����:��XAB��̆l#vV*�~��Iq�U�ve�Į󧷔�m��@)�W�6��,�-c,4� �3(Ox,ք�d��jzl�R �h���w��̫� 9�)�1�B�zx���IT����}A��wo�~�������]�Nxu,:���H����7��$�������o�{���,�J�G�{����a��,��^w�{?����YZ/������K*�����E ��\wg�1":�.࿲%����1�S�D5�+85x~�vD�^�+�I�áA. 4�CFq����?��3�Йp�P<�r�v��l6aSo��VWW�0�Wj|��by!����W���O@��\sV�uQ�'0k���m��ȨsӡS:�(��Fd���?TY�pVr��c����/^����$}�����u���=:��Z&�[����~���ځ�PطN�Kz�.��:_���h���9\��O�(i�Լ���rK��������`6i������i�픝旜��`�8�p�Jщ�%k�u���q���f��:�,�V����)���O�>]jn��	-�}`�6dMVl�����M\aƦWR#˫� �=ܣ*B�#�ʒa(XX����,���<�l.b@� 2@5���*U����k
��Q �\:��,Ke��t����e�~|w�iēQy��r"��p��h!���T+�֙O �S�/�
��(�&hj"FOy�)�* F/�FB0���i.	F����� I��"��)�ryY�d�)j�
6�ʾ��C��b��������g�*��nʦ��`h�<#$����aY�;��9BD�L�)Fyb�	
K�| �V �j]�<���6���s�̶���ݭ�u�����3����m4�?"����;;��Z��:��:��5Z��L��zc���{����>d���;�{;��c��=���=����ٲJO�ԑρHF��~6b,X��0����H����N#y� ���*}��A| �����-T�d��p�?p�r1h�5��<z�C�,܄�����M�rI�iPW��~HkRX���XA�M�h�3������tar�I�xS#Ed����&��4����d�`F�e*��q��t*�d��!k�t;�8M�����J�r����`��9�e67���
9	=�[�qC�I�`�/�Fvv���c$U���{2sŊ�/fCЬ .��F�#^eHb�>�Z�̿�~�B�M��Ъu�b�k��6*S��'D]$T����.�+�I��Aō�3�.�G����M��)��p�B�S�?:p���������~���������N�v �2���p��n:��=N��\��y;�0�u42��r��ZFwD�4��8<������NIw%�&N	'�4���q�^��F(�5���`��c����0b�p�g�
�X���,��*��Щ	�>y�H�vv�� ;���P"���'��O�2%�i8�(%�H(k��k+�'�$(9}E �y$� |Q��
Œ�1s�Q���Y�~�r�=�:�߄;{aa��`'��aK��Q{��ݸU�I�!8���D1L��H�!�@��7�i�O09��������ސ��	�vQ�D��ȋ�Ѫ
�c8s�DPv(���r63�N%dq��)BܨUH�CM#�x"
������ U;柊���i�<���y9>���ݞ�&+�Te)��Y�Y��nJQ6V���]���j�������d��z$Iʕ��Rq�̓2��
�඲P��9�_V0 ����(i�� s*��5ئR���eb�:�m�W"~��
���C�4�V���q$xk�2�c�~�
Ŭ*"D�Š�(���ئ,��VQm��2�
�-�LGT
N�S	Rk��07�#	��"�*QV��Ui~Co���*b윉z��W����,G{P*�$��Esz=�&Yl0ΙfX�g	@��	�x�`t`���(sT�B�EU|}&���FMUq^l�`P�q6��hl�����&a��b�I�$1 t�ii!�h�(+�W��)��Q��)��q-�6]�D��:YIRHOQ.)Tm@Ep2�4�7�lO�*�O�;�ԛ�"�iZ,�*e>�W�F��ڮ'�/��t�
�V��5�7�B��@z�,��n�js�Qua���;�.y�0�.Mo��zG���ULhQ��Y��d�������#��c���u�w%M�F�dM,�X?[�%l�⠶-�$T���;,���B`p��n����ղ�����PJ��&ucdLT�J���5�����0Cp]�֕����9��;���?%� ��T�7�7���gp���9���K�h	��E�P�F-#O�~�9|c��~�����=�w@�֙�"�����{��9ỀH����$p^=��7�Z�/�\כ�9��g{6����$�ߧʲ�ɑZ�m��<K�����|�*=���(�^��-�����p���Ǧ�^�k��V~�_!<�� ��]�����+b,0&���ϋǷfP��,���K��(��#1B�����Fm�c�@�3�`��F1vAH�����d[#\][�n�^����`�ɏ����/o7_�����Zm��3Zm5�lc��o�/_ѣ�xYek�/���h��j͵5Ijm�����v/�[��x�A��^}��=�ģI����޺�9>B���7\;��7�R�.KD���s/�Ur��	'=����.�s��mu4Ps�ϗ�&���\;���x��AX��cNN�sY+�ԅ4ԃ���t5g�]	��` qP'u��.��Mԩ���2"z��ZVU���F|�3u�Sz:�\K\!�S�� X� 䨁�|��Z��c˯:��G��;�Ԯ�M����X�Sgʍ�Լ�m����X�wl�!"��2]��nֺ�>���|�[�筞��G���'}�run����ԿY��ɰ�8�.���]f�n��H$?|�l&�b�@�,��6��{��abԈ���ɓf�(�ĭKU���YD�I|�'��湾���Zqs��2�X����j v�d׸�奼�����~���_�h���/��$��EǄE�_	�R�q���q::��E��	[o��
{'t�9�*(;���LL��C�m�[�Z|Iº��'x������cV�#T����|��ݧ;��\���k>0��V���˯���t�t>c˱�W��i�0��f�	�W��쬠��FC�\�D]a}q8�s�k	����m�3$bQ|���#�P¯�~}k>�=R��˒t�$����� �*R�ĩ>P0s��e�,��Nb\P|Aj4����9d�"f��"�\�͓<�GE)��_E�Ԛ�gRJ�k�R$T�"��t�Cǝ�Eb��p�?��Q�p�Q���1�b�M�5H���ޢ�Z��zK�L�0/�Q�n�;�1��S�>�O�S��������l�����o���=�~h3�N�������Ꭸ1���,�;`�����������?|�q=���n�����YG'��%���~��Wf�K������:�%`�f�X��KJ3��f��@��w=���Q�Z}��(p��=��	(Ke�X������t0�dy���D.]O�Dp�?�^ ~��~ N��Fo��lӭ�=+L��S]22 f�Vï[v�3�����[P�0֩�rx��%;�D��;�'��U=�a���ώN��E_k}kV�l��q�9������yݿ�}}ұ��']��ѻ�a뗗�zwt���ڵN���v;�F�e��AqQ�ھ�M����C�y������m����f�G��)o�����qwg�p���S�5{"�FjL�x�8�	�����T�ܵ�37�(���E��!��Z�y��C74:�d�����:�m��<;�A�m4L!4F%�O��Ltx�ܿ�B�;����_V�j�^���JH�Ql����������-57��fk��Y���1�T��P ��U `5��/TC�g!�`4��p�V�]�/��־{||�\~����a��^�� �8�Y��t$�|*�ְ
*$�9EI�2s��Q��jݛ�$�0b�z�Q`9��Ԩ&t,���Z�cX�Fʳ�0(����nKH�<(�,0�'��3v{l�Z����#���	Xѥ��D�L��V��������h����k�?����.<E3VY���a������+��g�W�1630���@p�p/6^��ݍ��OOO�gpb��}��#O{v�٧���c��$uK��������tK�R�T*�J����>^�����>p`T��j`�yT�z\G��̑�2W(�gI��Gr=ޅu�N�{� �i:~��L�����tmSRR~ڴ��ɹef�ZR�WMZ�f$�l�@B��O|<�d��vE+B���@}�ۯH�A��:B��T���(�C�;�҇C˔P{ty^�7�"ge
�K��ѻ$H;}s*��)U&���`����_:�̜�	����$�y�'�Ԝ������h����nҢ�����>��:�㸈���Q�����Z��v�M�Rk���������QET6�Ja�v�_�0�*l��w�b�{Z��T9U ���r�-�T�uZ�Ķ�y�I��u�r0�Ol��t�����zz��t[���m|)�;��$�����Z;�~%�����F�R�2Ǌ���	~
j����iES6�y�D1���c���a\K|��w[+̮�di��?@����`�qȘ:�+I��	���u�9u���O��*a�!ܕq�ɔ"��<ҩ�o2��%�+���ɴG+
tC�'儮>8�q�_�Z�b,a'P���zk�zLD%���	.���2j�+H���|�(cC�I)W5���I*��j�h5��rnB6��d7#"�H'�'�C{W��JN�<ģ�q16E�Ҏ��V��΢o:_�%۫����1�Y�&<7�1QDy�ݺ➮���<M�9�*ٵr�[3MK$���͔˪9�����$��_��ˤ�$>so�NW*C��k�ĠlS�J<���zK�JF3�	w�Qj6^�-$�"l�:�ci��F�LS	�\5QJo;!!+�i �F�f�n#,ۦ��4�¸T�����@8�7x���+�lӶ5±���9�w�Q����+%��m�0+�v�~��\qGf���V����o�̾�"�U�M�v�G��]�hL��x�5a3�3�}[�nVC�E��]O��
_��<��$�\m�,�k��%+�1��ڍv|��Z�C&Z�Y97sR��f�v6�����-�5M��k3�3�"�6;sBa�D��,��1�Kz=g�Y�����^���?�z~��\Y�f�ZX�`O�%N��` ��v�%�B=F�]�J���J$�É���}ޱ����aF��T�\1��n��-���B�O�ς�t�^=ý*��P���e��|"wd��;��<�v��wvv�����#AQ�<����"ͧ�S� �uҜ���i��d�}��կb�hr����1sL��tB�XCH)��<M
��b��TG��uæY3��+_u�t�c�7G�O�we��u�v�)�� ���V�X�	S�~ ���w�wX5	ɞ�C�"D{��#����2΂T�#�M��{�k��HA���@�t�ATM����9��x2�-	�h������6o=���ܲ�y�OMaj�4����,&}�_+5@��}]��P��F� HYw�f��P`���Y�9\�5� ����LG�a����ypH�kS�`U��.U���Z~�o{VT�|����go����k/��eF�C����D&������F����$���d�G�����v��E@5��T��0*���a�]L6�;��n���gC.n�Q^	��OU|�.0pz�H�,һ�x$��x�x���uD�lh�����������Q�*�P�{r:�	��3��?Ґ`�bl��d���!�����aR^�?��d� �f�A�ڔA��E�'WG�o�M54έ6j%e�ȥ�h�����(ƨ@����ξep����a6��?1�Vr������UB�(�T=P{j3�0��'��JDJΉ��D�I�Pa:}_ץ��;��Y��@Y��:��J���Z=�F}�.,n�s:q�>Ə¶7Tc#"\V2���-��eu��ե:�K��ө�^HH��i	� �*-����VDP�����}/;��PU"���FfIe�c����p?6���V5�0�WvSP/@.�oj��dV���t6�e��d�w�ҙf'D
��]���b�I^�kA}���@.����֜��h���9o|�o0ݜU���ے���"٤�O�!�Ildɞ��ÊE�Egh������հ���*���TmC��u�SDӆ AN�bJ�5�>��w,X*�nt'��@gN�6��!ͥ�%��\�ђ;X�N���&C��ז0���[�A�j*�x�K��.2�Y��_�����v��q72֡�@�D�*�K��cj��/s�<���>��˥TV"�����q�NL�^�v�,P���(�z]T���+�_�s�>�`E���j�e��p�5�8�f:җ�|>0��<m�y��c��hl�-����{���[}޳腤��'��a���]�d(�l�Y�bHK5��T�o�[��uӚ���틅�����f���1oҐJ�b!$kz��0�	�}S���x�f��Ev�r�(398���C%&�b<Ҷ.+g85�F���	��^z���{LM�Ae.
���ΰ8��8�y}�EҲ�Rm."]����:���x0	�g��0�q!��8�+Ѱ��v��|k!���xf��hn��h���泦�j6��uz��^�1h�6ck9�6u8����i�I���s7�۠����ٴ�`�k���L�)��)Y��r�'lԸ\���L���a�t0���p�e����-0�����]��k8(��bA��Ɲ��P�DY4�fj�)s�
8x�;vOA��T�Δ�c����dTW�VUҞ+��NA���I�\����UI�K��c�2��SqCz#'O>���T���0��:J[U��{�(0МZhL�[��0ͭZ����anbl���\�&|1�(��FMQ��Sx6c*�!h�G�q�~pCw���,�M��8�����V&j��}Ҹ�1�V���r��]��B�'�4��p�O ��Ǡ�n���9,S�cX��w�8pΝ M��,��|�����9`�BG�A/聘l�SB�E!J^���DM`�RV�T���Tb�vs9����"�}{�� �T��f��� H��*������� �I�
�]������x�i2q氨�S��G����5z��Iة:X»y���c����H�[S�i��z�=VZA�m��N��ZQ_Wy�:���=�����pv� `�|�)���|�l�n���Κ�-��C﬋(p�ښ/�c��$�Z��:�>�`ֱ���-6���)��HJH"6�c�@2��2��(C�7�$�-��>�s.�Z�<��a�Ѡ��8o��F�\x�Y�2�)�1�v�o<>4o���D���S�P���ݟ�C�5|����»�ht���U��n��eiۀy|zU�k�D��njJJz\�E�d&��j�bT�����%XL��gpGjƱ�8�ꇎ��/Qo1Q�����q,�QTɛE?,�d^ ���+�ß�J�.JP�|l�!hu�5�m�������`@N�������e�4�5�ֹ�[5��8$R[l�x���������g���$~(B��䏘��1I�Q�2|�1�����S�����~����6�]�m�N�4P�ӵ�7���i�.��s40�9^�{�S��i���;|�|@&Ejl��,w�ɝi�.��P��-�rY��	�ȳ�ƪ��!�F��Q\y��X�u�����z:G���Z���R�%�1�.�P�D�:Iї�-��K~� ��X$��w9�0׉�X6�K/�f�o�6������c!�t3��p�� e��_�7���6��Q��˭�m��d���v���)"�7��N��K��?Ǎ)��v�R��'�`L�\�&��~��~�Y�	�i �*)��ᢇkI�;M��g����w�[�=���yU�����r7l�8g��)�:��5����R~��.��/�is1�x�2W�-暝��iRj~gi�I��.�sF���㭹����rz�bQ�L�W�ad�VPf�'�s��^�M�s�l�Y��Q+��Xƭ$��̐m����֬��xחa�K���bZ�Uk����ӊ_�8�o���d��-����${��b�rU�|ު�G*{f�2�8���7��[������յ��/_<Z���r�z��>h�ۯ�o�3r�W��n�5.Y�Y�r����>�DM�:��)^Bf����|�Fu�w݈����̯��j�ƹ�t��(�P���A� |���|��f.d�����)�n��~GMӰI)��	qZ�DCH"�f��r�|�׵��"]b�d�}dy"����:q����ӟfSA�h���k��f�`�}�̎��,8D�l����X�U�l��E �(kT�ue�>�o�Z�Y�7I����� W0�?\�����G�g��]��+�p�N�}�Z8riٍ�Q*UgQ�F� %�1������{z6N, 0���$u�,A�dH��3�f.�Wٙ|H���)�n��D�8��~��y"ƀ�c����-��/�J$s��8|�	h�~�~Ҽ� �*ݢ�V�DΞ4%��^�B�����?@����+��+���k� �MZ�M��Ĭ��~��Ђ׺�(kjr)z���nG�A�OO݈��GIBH��\���2�kGc�:B�Z4/ 㙉ܮ��|[w&:������p~
�d_('P5zi�E�$F��o�S��^I�OD}%��Kkl��>�Lf����h(!�X©I}��$�MZ�5x��Dx���,y4魮	����l��AĹ��EOj��ǰ���	���ܦ���U�]�D���)M��A��1��'�)���x���ۯ�@�ß	��G3��.ҿ����l�?�#��ux�����(��{8[��M�{�3>��%���-V���������Mx��]���rP>�M�����E.�:]Tkц�����P>�a_9�C��8J0V[�t\e�ᘏ�Kv �H_������.o�ƶSe2���TSeN�9tU8E�W���G.?r�1��t���V��ϻ��X��T���bON��]'Ȋ�d�:h{�_ ���!�
�AHl�I��=�E�dl+�3��D�,��ǶsY���m��*40�峱��|��	~�q<f=�����s������j��<�
�xp���!sƸ9qH9�bIj��nR��a�� Ѳ$,��,���9��9�y�� �-k����@��?��CU!uw�S�7���	�=�F�eWK�]��Wl�u*ss��j&������K�s�����u����*���
�~���Z��a�E����!�f�X#���[����d܁��t�A3(�8&"��$�[�x��P4{l�Y�� a�e�s5���2FH>&19n��D:�y-�\5ah5���t���~X�
�+Y��X���px��d�d���a1p�˪�SDH�0��.QY�S����9���'Ѳ���R՛���I�QJ0�aEBf�d�G3�łf=F)���#�
�uՐx���{\V#���"=W(8���k������Ӂ��]aޮFڔ�K�`�8;�>N�k�7d�d�˼�[l��e"{Z^�gO	���!��_���<Ơ-FVWřc���k��r%tH�B����r��/��}�Y�`�OA�#H)�(Nj��t�((��?��U�,]7����ގ�W�p��x}=s����I������w'��|���]'<��
��M%RE�Wl���CΚ�Ge�d�1������\���7ǯ�o���	k��y{8�l�{�{���-��^�
U�9I6���!�V�R���E��	a����Tz#��=qa\j-�V��	rd���	�	+�>~u�܁�M��<�����Mՠ�&ޏ4h��Z�*��,=��x`3&l�V�d��V*'�h�4#��������ұ�qX�Sy}x��p�eg���V\D��5�O+-��V��U����*{Py����0/['��D�]� _`nY��
���Y��:j�ϝ�!�>bMw�-��[�%�x�`� Ak��Ǽ7�}yƃ��"��F猸�}h@�猓T�������{��'a�`o��[k'oa�[�e/��:I����T�m�Ϛ�.kr��߶VV��B�}��U "�j��+ͯ~X��m���7���I�6����X�`�3I+��DAs$SC~:q�'�K��;��]��"0[~�Oι 6���_��μ�A��V�̘�n޹��K�\ AZ�)؇��L�!�8��l�=����VWW���"���w�/���f�� �����O�Rk���Z�~��6{�" ��v�ta~x�Q�r�ӕ-vZ��&Y�@�G|+�'+���-�U[��Zl�o��V/؆�ߵ:�]�S�v �.:,֢o�#�x�l
j�w�����(�nF_�⥬��p��E���llt.�exw��_ �V�}�P56�E��[��AR^@&Yk�'�Ft��5�Fl?�Y��D�T���Bdj-^,�4�>��޷!g�U��_<�TB֝�����)ꡃR��!�NV��+r��a��	x���&�9�SO3��R;
�����Is��b�ߍ��,�>[8�oI��S��oJ�[[y8���"a�nf��x���L᷵竧��?��S�kk�����NrXDj7ߩ��J{�f��jQ���w_]�����g�a�N��`�.&b'�i���lV��?̯h�㉋Ӯ�48+a���,�+7�dV�?�����Ź��l�����Hy����#U� �?GD����;�!��(߮	�q�,	lp'
a�q?�#�U��o�v''��R1o��Q��wv���X�L	�����Q�^�[-/CװBiL�n_^���߄��h@Q�z8z"��堋���K"���s��V	�٨�F��w��H����e�_G�����0��������'�����G[Myj�5OY�`���O��P;8�7�À<�Ϋc��� 
d�<	�}o����)���P�_Z�Ӈ�}���i���=���Uvv���=�B��n�F����^�S��#;��8��z7T�,d����	�@9 �g-�Ͻn���X����:cޤ�4���P��8.�\�� �8H;�##�m-D�������z��	x�  �g�u�����o����W�D��P���R&k�u���]ѡ͜�r ��x�D6�:�=�G�6�����{.�	 ZC>n���l;�sg����3�MI�aT]\؆.y-{��1Z�/_��?����0���~{a�u�]�s�pF:��7�&��q?"-��e�rt�����B� �9A�-�z�ʷ��;����gа� ���&()���H�D��0$3GP��@q�Y�P`c�X�s�6�؉��*Dw7��諐��0���m�88�n�!��@{
��r����6�!#gLS/�X�:�|�_�P�-
d������p���T<	'W�"��'TUe�ºn����k��B�rg�.Z������_w��y��x���%J��I��\�[�S�\ ���a���?����۝C�ؿƍ�o��(�K�wp�Mh�t���6���x����N�@�e�>��Ҷt��i�	>���=!k��*�2!ʴ����	�Lk���u]'r�P�T{d�K�w����1KJI�kQ�zN'��gs�A9B����đ�BN�g�Ȃ�F�A�I�ek��K1}/��J��G$mE-�S�B����E���	g��Q$�4,�uzn�֣�p����m
A�a\H���qNP��uH����V8�~K��WZ��=x���F�Eԑ�o9�pdC�N�GQ���yd����Π%64���_��Ŀ�5���y����,�X���9u��8�Ā����xPQ����NNR&�H�ۅ&�-�C�N��㄄Mfbj�"jh8��/5��P��E��E����QeD<`�h�9I��k��N@�9����ꟈ0�>֡8��z�B�u�+��{~#��.�',�ːLF>;>ro-�_d�������y���� ��C�^%�(�X�#�]�`��� �|��������v��<��c	�����h2�U�i�Q�3��_�ˁ1�kprr㯦ڳ#_�t�g� Ȱ6|��V�����r 	��-�\�*�}Z�M�9���n��U�L}Vg��pP6���}0u��[��U	\1)��&�94��ue�;�k�N�LgP�����p@]���t@R��7�8԰����@_�6vG~(w�`��d��{�!g� ge��,摳��E�]�f����Ag@]�c�vc��rPĢ>J�L���%r���U*���2�d[� ̝�z�|�3�ڢf]�c��:M��L���{#s�@�h�D��w@��f��Ns6ۨ����S�o�{X\�����>wC�X@cG�� /�d}��^�/��>�M��V1d'"����*���6XR�}z[���ǥ:#p\��n@�;t���	�4/���a]wH�aX�	�x�A��e���`��N�B���!}�R��ǻ�u��D�r�$'��\�M0	��Mv�b5~����G~�I��h��7�&��\N��2Eư�r1���I��x��q����7G��*��7�1X���ΞX���042�p���u�O/AȘvu�~H+�?Dn�c���J�THm�����r�	9�����F�ۊ2K�4K�4K�4K�4K�4K�4K�4K�4K�4K�4K�4K�4K�4K�4K��y����f @ 