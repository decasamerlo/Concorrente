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
�      �=�v�8�y�W �㐲d��Kb������O;v6V&}����dq#�I�Iw�c���<�'�m.$����̬qrL�*
�B(01����k��Yj@����gsk��>ez�lol �z��|�h�ڛ���Ʒc)M�(vBB9�ɍ������8����'�7т/���F���%e��:t��h�b����}��������#Ҹ���������څ�]8Ѹ���ޛ�Ӟ����YjV^�=�u�����;�����;d�WqG�,1R�I���xL=(��I}D�T�!t0���I�`���?�	�ɍI���\�@�@Q=g�93NL��a	n1i�M�\c	�+��tQ��EШ�ZY�_�aw������ԁc|s}�d�7[�����j?���HO\o0�)�.����:ޭ�Y��]f��B��%��Y׋I���� Ɣ�
�J�Q\#�Qb2;a�����I���C�T'#H��3P���ơ�������ԋ��Ѝiq:jL?!C�:�g�'�$�˕E~�V��B�C�2S L�#�x9�t�<�Hbw���g����9�&�B�B�4y�M���0$�����F�,��񻣣���A��W�fX}���3p��I�'�~�H��xJ���夘4j$r��Hv�e�@�Z1(�][#	{�e��¸	�0�U���7m��m����o�pPF��-@�o�l�`
Lg������ބz&c�"+��k��J��$��Z�@	4���A���0�೙��F��w�����PS�&�_F�=��n鷭l�S�I5��$
��U;DV��=^Х�rM+���H�#,s$��""�����19��gN�׽�6�/��y�g���U�k��
���ͳ��v^���d<)v�\6B��Vs"f�f��ke\V�ge�C�ҏ}2�PǛŝŔ&�[ _�'�yN��#�j��� h�·탴��NS����n@%"�c�)|��Y�'o�^3��Q<�n�\aHuN����9m�p�97)+̵!C:r=�9&Pw��VR�t�R�[�����"ߑFY�3u1QE���M*JM�mj��+����TR�(^��gMȚ4Ae��CJ�q/D/��Vy(�
��
�@��J$�s8��iߓ&�F���<f�vr�0���ɘ5�T#o����/���A��w|9�?:<��+�������"�g����M�� �}1Ҕ�$�����1��=?T��]�f�z����<f�m�c"�*����h7nT�����=¥��#J?���������6HQ�!���Y���H!��	�R��nOs͠#Y_N4�#�� ^^F�r��F�4�B��P���!�U$�Ԝ:�\���ďh�!X�h�-���PZ��y�8��N�Eƾ?���R��!����)eФ�(���5��sT:�1�XS˥���h2��J�g����*oȱO�N�k'bR��5`��h��]+6DɎ�@�g_��,��I������Eb��N<c�	���JmNWw�$*	'
��x��t`bC��	)pMԄ��)�YYQ�Wufm��!�g�37�Cr�9�)���l�P�*A�:A�Hu1_'�2ƺ&��+�j���4P���Q��?���e�e?\��O@��$H�<k<���%�t����|5����lf��Dn�vg(bN;�P���Y<��"UY	k�8,����|���:���YNB��̆h#vV&�n��qy�UM�ve�®�[J����p���+{�.KxKĘ
M!���'<k�|��i-;�� E_Tһva�J�Oy�`�/��j"��u���4��V�7I����������wWǂ�V+w�����z��������9<�c���Qo��Ԫ쟼;�u����}tr����^y������sgi���C�1�d�A~��$ kCz���&�Je�F�=�рzC���1����L���aH�Β	^E�'�;�z=�'T�4ПBۍ�x�'�S�l%��x�'N�8ÿB��e��4�{��d���ݢvD_�Y���d�Èu���4���Ly.M(��rxEn���&]�d/`�����Wh%��\�o�(��WtBbwJل@����7��x%"�)	���_]]5�\r�2�Kr3,/d:�ح���8Ï	��2���ʮ`��@+�h���R�8�*��(�ҁ �e<���5J/O���d*�Qc#95�|V!XǍ���������o1.Rċ�?9����KH�e4�='��T<���ק4���]Աh�ooe�����C�Ͻ$u���z�wеO��X�q��U���6�$p��#L�E�k3=F k_��^���/'3�tx�>̣�pV��ũ�R�si�rHVd�m�h6��6�j?d;�g䬸��/r��]�9௒��_Ҹk���������>��V��Üg���O�<YjnЄN8`�>"MRn��:C���V� ��%���_n}@���U;�W�LS®4-KV�g�������E�@XM�ܵ�RI	�z]B�-�$ k.e�5���N8E�3:Py����uy��H}"c�ChC8���Ð[�-���j��k��L�cdX�&(j�G�����S��Q������#���@�+_H�)�ry��d�)i��6�ʹ��Y�����&�OW[��Q#��pu����ahzT��݆TF��t�����?�)b�;��.-�Wa�g7œ�jE@��%Ϣ��j���v��2Ȯf(*~�H��1�5�?K�����C��}������;tb?�'y��;�c~�g�����o4�?�%=qGސ��m�m���`�w���uO{?v������k@�@�ѡN�����v �e�Y����a�~�(��ک\����a���g��PΓ��4�p�
1��k��8x�C�pS�aN|�QٟiDQ!I/�	P`|6���HЁ��~p͎�P?cl�̋�K&��T)��� �(Gd>4��D��v�G�3*��3��_{0OgrO_�VA��s�Y�-<k�C�+�=����rGI�*sl8`o1�c7s(������7��U���#gL�d������iVHՒױ�"$Y�/�y6۳c�7��e���A��Z��O��j���Q	��F��Օl豨 ō�3�.Ə�e�;��l�,�_���V-59յ�n����^�l��s�?��a���4w�v"����	�a�e���Au&z��s[ϛ:�8��9ZC#�������iR�q|�ׇ��|�ZsWb���V��כ��Ha8���`N;:�Uw�pB6��B���ÞiI0�bCj.������&&3$ ����1����%�9�w�9�~{tZ����'d�c�=�b*�������d��Ġ�2��L,&�D:�/k�N�Xt3o�tn*P.��*�瀢�	׉�yh�셍�]��Tt��5bN�I�v#/��=�g^�S�����ߵb�Z9a�If!y���1'@c|�3���/�;����&����PnI����d���]H%�rbe��̄:+aV(�mb��[��pX��^��Ǟ�������V�p��΋��H�Rr����M�27����n�Iy$�X�b��kE=PS4#��aA4 K]�$Y�ؚ��|�eK?!�"���n'�"�-�}C<Gv�F%ri��nдȡ9|Od[��M��2Yъ6'�N�4-�������_���3�t����xq#����+f�!a,m%Y�>�b�?d(VR[K�ZDjB��C�iIja!���L�ԛ�<`���a�(��JS�f�	1��H*�"B�	���|���z9�#��qiE�-ZY)��y�t��Ԭ���s�9�6P	��1y���L�ʍ�v>�ܾg�����`�`�'��y#2U��n�����/h��ݕ `*��N�G�rj$!���<':}�	�U��[p0A�G>6҇��:��%cR��pVBK	EG[Ͳ��N�)DWh
�����r�ʠ�\����$�������-�N�٧v�:Qev�ſ��@֚06�)�Ӫ�2��u�k���ԗ�H��%r+���˅�p�S�#=Ms��e�s��ua��?�/i�0�>��^���N��k�PnKH�h.����f!�6�	���ŎgI�<�ZL0��5�6!c5���K�.xQ}��	��/�	�tHڃG�����;U���V�W�|R�P��Χ�3�ȘXm+��U��W��BL�u=_�vW���+��G^WV5 X�b��/�.Q��:kM�XG�${�/N��C6�5jyz|����+��b��×�q�= y� $�h�E��0��N{{�w��Zpm��v0�@.�S����E)&W��g7 �v�YD��,j
_�dʳ��Z�w^�RŃ����r�z��?Q����׀>_�_+é�>	�|jϙ|���Bx(��K��w9"G�z������,G�x/9ߊA�J�D�"@X	h�g��\����Em�c�@�s�`�@Z>vAH?�)^���j#\^��m�^�Ď���/;>;g��`��|�ڮ�Vk��F�h�լ�����m�>����Y_�z����F�[�h��R뫍 �W_��x������-�@�������M����=6Z7hȴ��+A~�0Wj������Oh���Sº���b�&_UPs�+lu2��8W��&��\�,߱��6�aaO99s�E�P�ƥ�Q���&�+��mj��� �N�65�h��8\cͬ7�Qk��o��U��4ҋ�8�Y7�=eO@�����y�1U�� +	�5�W�4��c�?qp�UG����vǷ��� 8k���܀�A`�¶�g ��A�:xQ&�`Rve0����3Mэ����Y�|lK8��n�@��-_{B���W��;�f�Q�bn�i�Y�7�8�����aR/�����q�~�@6���C��Y����v�\f/���`�ϙr�<W�$�P+%���L�:V���<t@M�.�����6�0����wSǂ����f���퍇�������c��?�Rr��dƔ��
��l4[E���#v��a�:;�H�;(�CƝ����~�}M����Ӡb��#�~���C���3`_��t�|�C��`�N)z���S����tMl�FO��N{q-#�0��;qH�y�d��v�h���XW؟]
���)ǚG���a��9�(������H�������|�=R��˂t�$����� 2Q1-�(X�J���Vc9�6.X|If4�N��-�
�$�|;Ef�sշH��']���&�5�f���:�dH�NE.�so�4�]oF������.����.#�{A�0��z�t��h��-����������l�����]G��2�k��n�X��5�[���6���߷OO��� v�O"7����/�����q?؜:�{;��� Li���?�;��'���U9������}r��Y2ON��G?���޻�п���K�;���1~?o�N�Uac�RI����_���H���i��_��f�D\MA�`a`6���â��ˮ'Ft�9�����~ N��&o��|���+L����[[2s V�^ǯw�\������[Px?Q��r��[{N�}9m�zh�W5���>99���}���U;p�k�+b��`�S�#�u�A��iǶߝv�_N�t�[??'�����_�}������n��h<o�8�#.j;�@����x��4����������F��77���}������Oo�{����Eۓ�jhfƤ�wȳ��!���������a���d��^�^�Q❭U��9ȩ0TC���oM��8���yeK��`�m�Ƞq@dV���g[��F������y.�c9�R�"Ɏ�ʒW�7�I�SԐ�0'$GN��c�[��R��~�t7  ��Ȋ���U�5$�h4�n����&O�,tx�><$��o�/;��r_n���q�t��
���r	48 ���o �&��l�ԙ��4�����e�i��Q\�w�U�)6<�������,-bRڜ�f�~���X7?��_�p1ǴP�"��`�K拀包"ѶC�����,EbOv��!�\mKW�'���j�
��c��ܽ��`9:5�T�j<f�F�2D�N\�iaq�Ь�|�NL>G�Sv�z�H'[Fe�~m��0b���ښUj���R�n"*"y>�l���迪��ɓ�����'���[ylo��TV,w|6�\/<�
X���8!N�}�����Uþ8TжB���bp���c	kD�8Z�9�Q"zE�X�ؚV�OEvL�ǃ�΢V��-.D��×R��OVC��$q�/*eWjiA�z@JvrbX���J�$J_/����� ��I��t����i(E5i�M�ӱ'�\�
a�j�&�
����T��V^�1���k�({�}�J�8L�jr:��r$���~$�%t���Ƌ�ho�C��B�������S�w�6�R�����
��ن;���g/I�?�"o^|l��4x[/_��	%��bx{��?���8�`��މ;|�*��r�d�8LK��nj�ɶ�d1e�K*L�R�:�|:�������������|���-�]������H4��8�C���j�"���2S��
�j�J�+v�&'��s�=����̻��,��ʈ펹'��ݖ�q��`��%�V֘]v�di^�#�}�,�6��2�R� ����pL~��'�S0�$�ֹ�'N5�r$��G�������	��ҩ���������$��+�+m_L[�D��o��`�3"J��}�pG k������Y���� M)�Ի��n	*��*�u���4�,�p1˺���p�P��7��zt�5���Qչ��^)ylf�9X�M勸f%�2�s�"C�� ���F:'��!R+X���zk��yző(�W͡?7ܛyz"0���ȳ�RV-	���GMH���D��I��&~�Ѽ������]?u�"U�]-T{*-e��{�OcP��.��4��,e�7�F�ts	�\Ө���N����4��x��nL������*:Pa4�oal�&NO�5ު%�*��Ƽ}Mq�d1xI��­�h�&�J���@�"�ꠝڏK�w��`�q~XF*;�����)�؄�%��Ez��H�_��u�=�6�Pςn�ڨj��=Q	��U��M���5A�j�ua\[���;cX��(�@�R
Ѳ�ʥ�MA[Zx�ըX^ʗ����<ek��젲P���l��|;%���U6���Fo�L7*"�T0=�yq�����C�re����b���1�f(t�Hq��}A�ЈQF������~�ep�6vv�l����῰"X*l��b,��8#|K?�����勠"���m<��O�u��!��>g<L���]�`�?����`g��������zx�r��J�V$�8R��y��{d�G�?NBF��݇1���g~�4���b�"ݗ>� F�å���'��񱡹�ㆳ�����f�[��:�`����>��m��qڕ?e�8i�����$|��%���aM��iN�u�7�n��8R&G�����)��.��d�ׁ��u'Q3��4��&�>n&��y:m��;{4avؒ5^�֘8�-�/T����r�\<����+�օёr�뽎��������k���7t*MK�@�96�͙��B��W��7_�
?�-��-s�"@<i���Sn��r�� ��H�n(�O��e;�5��� �Rs���č^2[>��~ut���]=�@-,/:�l2���؟̾�x����d�w��M�l�[کRNU'K�R�h�⴦D_��uT;��M�S���7�x��*�S����'��gL��e��Б�j�n����ZA�����a�	]�����Q��P�{9r*�	&�ӊ���6�� �K��i�"��e�3�0òyDX·$�fA�b��,2_�2U�T��j�����f��1��w`�T5�.̓��KS�r�^�]��?��EG6͖������e��*��J%@ikQ��0��m�I��T���/I��E e�u[�V�/f�.veQ�(�5%�(�k�:�LƧ]\�w�|�D.&þwdgS"\6
�����Ŷ,��U���R�Uj�� �?/a;DY�c2`T2�J�Rm��؋�`�ǔx�H�`��YPY��#�i�=�����BЎUͩLW<|#k�����Z��v2���J:���*N22��+�L�"��:D݊J����)Y�����?������u�h�(� ��n�U�m6SPwd����1��F��F��)>l�Zv�ǉCw�<]T��W$>M�6ĸ_gX�Ii��$([|r^Y|�������̜�-f��
�A���TЗ0�v[���v��kLҽB��Y� ������i�dyS�*��y�zu�K7�؉���ezVyu;v�T%V�%7��P��Y��N�����ܚ�en���x�2�h�Q����vR>��1�%����f�vj�����B���v�%9��2�E<h�jX��m[x-lQ�}��LC*Jg��fr^��x�W�~�<l1? +s�s=�,��VaY��j��RI�%�����$~�M�T��ٛ5/m�P2��kUu���֫�q�=U���G�K��0ݪ� -�05�r�=�,>�k��I&N7��^m[�ݮ'y�n�.N�Ԟ����σr���ŭ�R��a����K7��E/rp��������ls1)엍��ie�0���=zţ���������i��t�|���6�*H��G_�t���E�\��HW�vj�� ���A�|8ff��: y� {���&��W�[��z�Y�� ��ݫӿ�D��9�e	U�}�Oe@le���Jk�oEQk2޵��z��� Sb�lT�A�eP2+�aՓ͋�4�IO!r\��\���7�9��w���x��};��>`֫��A��8NqW��h��g�N,��[��ޮ�3�m>�[��[�6w$n�jNC��LlY���/�T�����Qj�i,L��W��u-Ň�E���E���[(���X��<�c|s����M
@{��^<5z�։��A�G���,�%^eM���z�ڻ��m�b�`��E宻q��r�~��p؊Ϊ�Aafk��p���W�8��$U�ظ2zkn&���f���*�<`9�6^���6��g�:7z�@���
/�J�0: �JdB���ě$��9.�l�#6	/���$`Q�x{i9N���}�ǥf����x�g��ߑQ�	�螌�� ͦR�ⶬ� ��iVJ�䲼������z�;h3�_�R6��9Rt�Y���Gs��c.|���(��dF�<cV.u"���?�}Z���*��R���q�Z#\�v?}u�%��PB�	�%e�>��_e�*�xN��anF0�'>�S5��{��)��giNM�L�Y[Tn�cH�
��jםJu\�P���*/�.��L� �Bg��U��R�F�ｖ��ֺ�=wÉ�w֦��yZU��XhbX1��J�3��X,uCwO�W8����D�vdT���M]�y���	�_/�Gb��5��#���#��.���R�LA��/H��+�<rc�J;�-V���)�����_fNۦ}�c���%P�no�	���Ȏv�}���,�� y���� ?��8U�W�j
�-�X^�޶�L��t��(�a�aӅ!���.~r�L���l�p�2KH�%�8jNY�w��e�e�M5cH��4(P=D��\CT�Ӣ������y7���L��Zm�p*��ac<�w�v���v5����kf��ə��?$��R�����"���	Gn��Wp�H�Iz��bw���I:�����9��[3�ǲ�9��re�=�G=[ѭrc�����[Ϸ�n�	��b��|N5YP����y�xam%v���������w��5\�"]coL�3�Y3���\�|�ae5�fg���`�kn�H�����3y	��ښF'M���Ouo���K�2�F��^�%���m gn�O��܏Q�m�cY�C�&鯔9�h 컪	�rAZ��\�Q-��Dp^��9�of���TH��G;��tz7��$��e��]�p���|�Q�'1e��Q;�8dǇ������ 
��'Y^�!�b�0�w�Jm��ø�0�	�]Lb���4
�# W=�H����).j�>��Y���1TGጆlx��럇"X�)D\v���E�i�w���93yל�5�e��?��X���WĴ����ڸS1,暃bBA��X��4�Q��.�Kf���㍹R��)�bQ�p��m3��@�s��Y{��Qھ����;����u�����i�G$�r6��_��}��W�˜�l�*�,�|u��T�_s+޶���S��`���
�b�1D�JU�rު�*{z��eY����a���j7�F���+������-�����z��>�Ճ[/�o �J�W���Ӓk����N���{aI^_P��LR�eJ�L�j���I���(/�U[�j�|��W|��a�|��W��٫+��l���{ ONA���Li�轤��ĸXn����w��n�4k0<���"]�p�,Q����)�_i��%���UX�;���Z���!X_֋c�^)+�#.vE,�ʀ8,�hQ��2�jM]����.�]<��S��������k����'.���xJ��ŕ;:��U���'c��TjY�r�%������D��>J�K�& }�&^)^%��Y{Q6��dq&�0�$���kw�}�h�Ջ���H�d��&cҾem���/�J��㷘=��4��E=�j=��R�谕v��MA��{�3����T�>���\�|���gs)�����m�%z���M^�^漮�����ϻ�a�*Y�=?uSB����}wCQ�����U��3�:E�Z��cTX�P�x��6�4���h����Es,�P����^��1;,|��rT�S�t����?��u��d�,,��1��xc�+����h��[W�}E8]��ffY�(4R{��L���詂�J=|�GR��2�5NUg^�x�y�6��XXQv!�67<�q�Ɇ}���o���x2���z�8��6*�?|������B���'L��C&��6�����?�X��-<8�9�x~��f���zQ|C���_]�(���ᓅ���'3��i��8�(�'`n�=�;<����&�E�&�ȟ����Ob�����`�C�<zP�"R>��#���gc'17�n8;{�0q�S�\�&"o�/��:|�K���?��PZz��D���!NN��:1�E��f+�:�ww9�À l�D`�xcRq#ϝQ����u��.���a�e~����MB4�>i�8��(��|�v9ߴ��Xuأ6�s���*�nB&�.JZ�k#�[~�����@�Ze�?I�'�h$tG���+>����w���T��nQ�.������M�����
�t�����1�`2�KIe�8Ke)�y����0Qy����91�m�3���+����4�/� �e�5���K\��>n뭴��M�7&�G��}5+��M�Jk�r݋Q��ї}<�:�A_om3�����j'.P'���$��4�eG�%�,c�VA���G��VP�m8y�z��|����gg�W5�(�C!zHٕ�}�0˺:P���7��)[�Ѣߖ��f���v^�c�5wWs�q����	'�Y'e�>����6�v��Gm�\N`%!)L�k�!���8������Y{�����"�Ȋ~քE���B�{L�<=����5����˱`�8)�O���&{\�L�(��DD�_�p���x���ˎ.M�B�����l�b04�.���%gv������FY�t�ʩM��`8��nJ�1`@8 ���z�k+"������b��lY�1���_�g$�2�g��VgO��D��%τ��AH3U���D���'�Ϩ6�����x#��/��w������9����n�C/�7�qZ:�3Qֈ��nv����w�EN�	^u��Ϊ���͓��'/�ph��~�ŋ���2�;;���= ������;�_���(�܁�Z��<:��RiH"ӫ�q&(���	�c/�ju�⃎յ�hC��'�/׆��"�+���"R_��a��|�W@���-@u���F� :Y��tx䣆�������D?}>l�]�3v��!�0��3�9����^�7�C�jЃy	���;�5�����I�B�`�]TH��D�F�ӟ��[/��z��L�%d�� #�����0���Vbo�9��V�<�IF��s�H��dy��H��1��8��NX���a������o
w7��͝9!N��mo!(BP$�#L-�����P�u����΍p ��Qp���(47l�h�Ρ��z\V$�W��R[�k���l��_Oq�>I��@��	�fL����F��S�q���F�`���_`���E� �<�9�� �eK��1�e�d�U�X'��xq!Q-U��������l
���@��8��'��B2�/�A�aS&�w3�Z���������pS���S�pN++(M��-������2�i����r�^/����A�⣵�����>|b���=z�������R�ԟ�O�xԐ��1o8
����U��ؽ���X�y�밌qd��)7��k�W��_��|u�)b��S�{�?���X�q�m��w�O���%�jvJҼ�?��-�JS��1����i� "^{��xl���z=(�w��$H�3^�C?�����Rk	�с��s&lCvV�d�M`��Dj���~$�����n��z���0N��4�|ޏGЍ��\�Mk"J'������K��k�?Oi��xy�,%�0��Ӡ�z�3$�n�Ǫ���d7�}�����l?��z~������3�:�|q�r���_��/^�}1��:�����O+އ/�3��!��bo��u�©7	��{κ�+��׃5�c�{���v�s�}Nڍ;�yTr�b�`��ަ�����M�Վ�en��x7t�����>�a���>�;�=�ĉ���pg�?!.@1����3�T?S���R�7d�r��O b�ؾ�F^t
T;��^�`�:`���r�B�>����! �8�Y�h䀫8��G������y��^� ����mBa��]��^����M1�Q���l���~A"tl�>{D���b���`�J�6�%�t��G|z��vcR� @o�%���'�}ǽp&C��:�$�
�M�?tϽ	(ݸ4�aH^��{q��@�ŋ��K��;��c�o�w��!:pF:�(�ա�8lзH�o�$lp&=޼�z��N�����n���Gб��4�.H�L�RC;H$�I�Lb"0h�DM��Y`�B)�xg�![�dg�[Z��p7���<A�[֏)��[���:(�qLdGEX1��:td�$��4N�lvx�{!�/�
�ょ�0u ��D/�8`�h����� ��R~��M5��7��5�źSv�c��w��=aO�Z��h���٫�퓽��:	��FmQ
�a}�qN�[�6��0I�����s*�����_�2���/ �}���ݱ;�ܢ-K�p��������P�e�ג�n�=}�
��q�7��q�˚��deJ�v��y�t��	N}'�ڲ��d���w� n�i]g̚RƚW�����Nc�Q�#� f�@�qG��;�1J�#�f�c��|���tټ緅���	�|a�#��!�msq(�nHJ�k�pv�@�K;�q�A�?�I��[�o�33(��_(K�5AJ*�!�I"�n�}������|��ͨ��6��덇l��	T9̔�/B��s�8�W�77���~�/rm�w�0�RV�O������9w���<x�ImP��?j�(XGɀ�'!�P$�m� �ȡP�J��mF3��Q��4\���\�z(۹�"�ՆR����V
�QҞ/P*D4�$e��e�3�{|�C����[��{�C���������_6$��8C<BC��%���Q�N��T���y�}����yf���$�(�X�-k�`���ƛ|���ӽ����.N�%l}����
��t16�e���3��m�)�1��+pJJ㯮� �T�ש����ak��}ݸs'Q~��0_ڴ�岁���g]�}������52u�ͺ���~N�9`�H����*K._��]2�����q'��+�N�7y�'�������>���,�*"p��:�S��H��/�?c��gs�8^� ���S!����(�Q�|ͪ�!�3MMp��P�����L�9(b)7\���q�.�Q���G���^��-���ᰚo��� \٨/rՕ<��q��#�r�*f4?��K"F�-��AbZi2:5��l�q�/$���_�q��xu��u�ǰ������o��.���<�2�.
�'����M<�E$�����y�j���i��n�eu��6���>�hy������I��Lv�OH3���C� 8(��F#���) B�πB����'u�R��\���C޴X��k�X0����0(��^�c-����g~�I��tֺ�l�bO,��2E������i�����n�{y���w��x=[h��ھ!�����,�=n��N��Z��;8^W�Bf�ks�c����U��၎�Zɩ
��j�ʛ*��!�:�G��b�i�[��,�ųx��Y<�g�,�ųx��Y<�g�,�ųx��Y<�g�,��s������ @ 