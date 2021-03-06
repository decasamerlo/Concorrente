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
�$�|;Ef�sշH��']���&�5�f���:�dH�NE.�so�4�]oF������.����.#�{A�0��z�t��h��-����������l�����]G��2�k��n�X��5�[���6���߷OO��� v�O"7����/�����q?؜:�{;��� Li���?�;��'���U9������}r��Y2ON��G?���޻�п���K�;���1~?o�N�Uac�RI����_���H���i��_��f�D\MA�`a`6���â��ˮ'Ft�9�����~ N��&o��|���+L����[[2s V�^ǯw�\������[Px?Q��r��[{N�}9m�zh�W5���>99���}���U;p�k�+b��`�S�#�u�A��iǶߝv�_N�t�[??'�����_�}������n��h<o�8�#.j;�@����x��4����������F��77���}������Oo�{����Eۓ�jhfƤ�wȳ��!���������a���d��^�^�Q❭U��9ȩ0TC���oM��8���yeK��`�m�Ƞq@dV���g[n�F���
����y���#F�*�hW����IN�e�ȑ86��̐�cG���ݪ}8�:?p�c��� ̅��$.N����h4}�d5y2큢�M��ioZ�������/���{{J��h@�K(�`O���ܻp{R7I]�ɩ3z�iN�F�����z'� �@-�S�*;"�{3!E����qnsʁP��a"��GGǺ��|�����CQ��z�	/�.v�3�D��V���\ٝ��s�-]�Z�d+ëʟ��0:�w�.D���TSP���bF��q�Zd�E5òZf�i.8�E=N�9p��YT#�l���9�Ó�t�֤R%k� ��vQ��y�y��fN���Ǐ�?[K��ǋ��[yl�b�UU4�`t�_�x��(`vN���48���
���}�QA������w��_Ķ��D��Z�9����T$DlI+�Ǣ?٦��^��ga�<y��(�'����S�c(��4ʌE�L��@�-H"\?�����x,�JE��$J_7����� ��I��t���ѩ(E5i뎝ӑ+�\�
a�J�&�
���D��&�����a��9ƞ i�+N&�-9��Iq9�I_�?���%�����h����IE����5��څ���ݣy*�\C�OA��'����F�;�D?���h^|l�)9,�������B�*���3�N�q5N6����>w��^�z�Bĥ��p7��d�u��%�fH�A���b:�#�G'{;������'�����[j�bn�30H$ّ��gQ؆η9��Y�+�ebb	<:���>W��MN��`{܏(��we����{0�P�p[��5�5���XYcv�A��y��Y_�{�%�m�@)�(e	]��?FG;p%}�LU	�!ƉSL��l�qD �Ô�X�0q���,�1�Oɸ���NC���J���;�t���58����R$��3\H�h%i���FV�YJ<� M)Wջ��n	*���*�u�N�i�Y6��2K���p���3�Gf�� k��=ģ�s	6E�R���Zs���Q��J�y �&E�|A��N<'��!R+X���zk��yző��Wɡ?7ܛyz"0���Ƚ�\V�9�5'������v.�N��T��G�f�R�~�v���4��v�P���d�5:�>���ƻ�b�T8b�Ա(K�94��C�K�H�F-��p�,��f����dua�l��� 6TЁR��}+cC7�p���V)�W�U�0��k�c!�i�s:��ne�D[71VR���aV��\����eS���22�)�8Wf_ϐ�&�.Q?.�{M/E
��r��k��ԙ膺t;�P��ݲ�D!�7�K6�g��k���qm3�d�a�u��� ��񐉖M+�6mn�y�Q>����-o�iʖ\�d�2S���l�D|9%�\�U���B��L:�{*���|���ف깲ZͶY�\���U�
L��v��1ʨ�5�lA�7"�o�N��N�Y��k_��R�#�c%��[�a��.�������/�ԐK������Ô���ef����_{;�㓣�o�;��w1� ����HF	�x�D�g�w��`�X�d�c���g��4��� �4Ez,}�A�X�K)%�=M
=⣣��コuæ�f�[��:�`�z/����늶i�8�򟄲K���V]ɳ$|ʏ�%�x�ê&$�Sc�2 �'D>n���q�L������S ]��H
�}Z\>םD�4(�Sէ��O����n����=���҄�aK��2��ľo��B,ʁ�@+��%��L���k�y:R*`��u���M^_K#���]iRE=���;tgRkS�����o��2?�-���%s�,@<i�j�Sn��R�� ��H�v��'[в����d S)�������F/�-u�_�����(��eF�#����@&��y��[��G����Y4���f��'[{��v���C�ɒ�T��(�)�W+a5�NtmS��n����.��J�T��j�i�a���	7��c2S�������\/(qz��]<mB�b���zԻJ&�^����i���b��"2@��$V�H�|�L%ܰd���!��Y0�'[a1��׺BS5�>�nrE}��Ii��,(�X.UD�FdHs�?t����r��B��.�k�ǑL�%C�cV6S[fE���0��L��%	BL���2iБ�vx9�Q���`����J�%�l>Ve�Q��N�Ƥ�~�^O]ӄ�i��9�9� �a���1.+������[fyѪTGr)q�*5�n������10	�E�U���	�`��@��#J�K$V�W�,��������z�lq!h�j�&�����O���t��o;���B:���)�2���L�	�v�h�nA��dbr�*Y�����?��ԍ}c�:r�22FΟ�.��m6SP7d����1��F��F���>l�Z|����>�y�>Pe|^8��T���~�a�'�i�� gl�IEe�1���[X*3s|l�p;0U��G�����	��"����g^c����z�ŷ$ę�M�v�����It/�W�x�ъ����]bg�W�cgOU��E[r3(��(�k�pp��|-p9��d-sCL������E�{��U,��P��y��?�ln�~��aV��:���)���+h_R�*�_č����P�%�׎-��Gp]c5����Y���b��ۂ܏�'�-�de.{�G�E�,�UX晬���[R7AIm6�>)��JS3�y��A�K�y(y��;�t��d֫�I�"y�V{S�旰�~�T�@Z�aj��:|{����W׷�L�np���m�r���)�}�8�SzB�>�yf��:*�ؠ��k�w.^�/wz9���]<j[�K�6��~Y)89�h	�ʩң�=Jr����L��HG�o�tڢU����'],/K�.��"�屝zĲ�|�� a�8ffԎu"$@����Џ_�o-D��-f�>�Bv�L������/�,�6�����Z�(�i�Y�����Գ��L�3�)� dR�c��͋�4��w!R\��\���7�9���#w�f��8�{��Y�n��Z��6p���`�F�}<3Wb��ޱ'����>���s�wZ�dlG⎭4�o���Ē�J���LE��ol�f��¤�z��\ג�隵���^���x%���k�R��s�o�#s��J�Z)�O��ǿeN��͠�-��s�	𜨲�~�m=qP�UwI���:s}��0pˢp����P�C��P8lEgU}�0��y8���+I�fa�*yl\xzkn&��'���=U�=x�RLm�D�,���jen����)l7^�0���qa�ܔ�'�;zSw<fP�`�v/d�����<Jo/��΅�.._ �q��00m(��$�wd�e�%�'㽡�l*%/nKj
��&��O*ˋ�Q�I��'��6���(y��O��=��Ӝ��:�Z��y��Xx2�I�1U@���� �1)��x�Y)���8q����/���#'��x�sI���y�W�
*^�SK$B��Q̏�O�Tt��ko�GA��Y��7�o������>P��F�9�G(����l�`�} X`�$w���f)�"K�^�Nzk]Ǟ���w����EZ��Xhbx1��J��	X�u,��������+���X�	"6�2�@¦��\�LP~J�7�䑘-v�.%���t���
BP��LA���H��+<rc�J���V��)�����_&N[�}���+�A)
��� ܜ�/";�Q����d���W?���)���ᩪ�ܲ��e�e;��L�ԊB�I6V)n����2��b����J<!u�d��(9	d����m3���Cʌ�A��!�����%�H��x�Hͻ�d^�dŗ
hˇS���Q��˜���9��6�]3�LI�Ԡg���!Y4������e���XMr����*^ .���~w���I<��O\Ԕ�Z̭		�c��@e�2�񣞭�V�1E�[�í�[�/n�	��b��|N%YP�񰠹�x��r�:���A�������]C���56vG�=C�5����+���ڬ,��d�1�wL�b�]	q��>{&/��	C[���ɸx��T]=/�����<�DT}N �r�����S�!�c�k��Xf�оH�+e� ���@B����8G8��(��K�p^��9�o����TH��G���t�0��x�z!�<�w�O���ʊ(G]�8����^;�8`�|��A�{S�dQp���B�M����3g4��&|�:�Z3���`�I�����y�*)�� �E��'4��55f��0�ѐ��~x�8�W".>v��N���v��:Ș�sf�.9	j�H�W~��g�
f_��b�j�N���k�1'�������{� ϙݗ:�7Ji�'+�ΊE�͹�V��|ke���Z�7d�M|h�Fn��@+�ˢ.��[̃�ǧeo�|�ވ�~�j�e�^�*s����T�����OS�~�e�4x�ʊ�N�ڃ��+@���4�_�5��mx������"�y�d'7[��K�P��6���]YM���h}}q��m<�������of� ��Я�y�9��e�+�O:�?�^�%��{}Aɟ23IՖ)��?������O�o�Dy��Z��P���,�E��5���m�����^ݐ\f#/��s
�t�@`J[��%S�M/Be���	##n'�n��(V�jA�1D���y$�>����q|~�1ȖTzWA�7J�?��@��!X_֋c�^1+�#.VE,��q6X�Ѣ|	y�՚̺2V���]�x>�'_��������O�S����O����k_�M<r��;J���/gQRk�g�Mu�z�éa�c)\�o��+�Z�pɐ��5����$�3�')�'��~�bqhW/§#a��c��I���-����)a���a����(�]u�� �Jۢ�V�D�V��BǇ�/��Ook�oPa��Z���)�xv�}����گN��A̚�����-x�F��%���Z?҆��d���ԍ	q�wlB���-�>f�r?��ct�5@K0�
��/�Ӧ� 5�����X�h���x��ԋq1f��op�W���k�����cy�m�����t\��S�%7����ˢ]sm]��-�Ht����7d)��H�u�3E�g��
")��!I�����U������4��b`�EمL�\�4š&j�͟ӿ�r/�$�.i�F����(���1�G+���6�d�1�n����(���,��[xp��rj��:���G!0q�������������?}�X���'q��n���;�ajM�\&�9{�w����������Bo�/0|>�|o��(O��b�փ��9.F��Ψ?9aϏ����X6��� ���6f�#w�30���R��eZ��Y��
�7Q�����F��|��#k(�����o'<�7x2r����wc��3���n���ǻ�w'�s�;��&Nn�;BC9�%GH��{ŋ��b�,�Jw��o�e�����W��л)��M��
ALy��r�N(���H�dZѝ�.?�
�|������	b��p��)���_�i��k����a" ��zsȜd�N-|����,�e� 0-Q���<jx�TK��Xuz��:<�dL�	�9;M~�S4k����VA=)j5=�_�c��;v�ۍ�{"�0	z�� o�~+ɞ]����r�I"=���.����]���]�gk�:��Q���vx�,C�dpѻ����; >�̧�����k2�{�(}:W�~r��|����c���x��>e�1.	�f�j=��i���ڻdY�~�|�{�z\+���8�p%���5q���V����s����o?� �ST{@�GR�V�^���Z�DJ���\����ʊ�S��?N�}��I=���4=�ᜫ�Ǆ3�g�k@�����r6S��`VBj�?t#�x�޵%� ���U��$��EĐ�&�/���=1͵k�d:߳���j��U��F�ӂ�4	"*o�5������Q5X8�Vr?hJ`�F"��lYeX��X��F�e�d�3
 0>�z��  �ͣ�5·���Co4�I�0$S�Z.Fc}E�5 "+ӟ+�e���6rM$?#�i��'?��1+��96o*/,������u_U'9i�?�(G�Ƹ���%pV�o�^lw����{/�^��q�n`�I��(r	���	�΍������]q<1E���Փ���t�	��L-/d�[7�{}/譱*N���,������;��3J8�w�g���U�n�`Nd*- IdZ�Z"^�9�d�F߮��i��2�l�I	�R-x�+��K�W 5�h����r.��9��j&��a�CO��	F�:tw�������0�'|�ھf�~�S�~�b]:76���������Yp8�����J�"��n���k��z{~	T5�t]��]�iA��{�PX��j�nO�̛�肒 ����}���rܑ��i��Z�gґ����p�H�����b] �V��'ƥV��ǔ9�Q��n��8��3\I"`g�h��Rx�[�9-퓜A�ݐa
�>K�/W?3g:�(�ax�?ë��g��i�h=����l� 9��G��M�{/��'ݝM�&\�e%: ��GF�H��[/#tD���'a9��䕧���+��!����p�����ڛ�Q��,�fk0��_�&/�g�4P_�P}� ��D/bS��$Q�@[UX>K�����f�p&����y GF��j����¶�'��l�/����Bl1����!l6p�<��+����@q��ܻ�9�L��_��C4�*�/��Ȁ�:�Iѳ8f0XD ���<�~N�1�V3��E�9����ۊn&�?yp���������>}l����=Z����sw�}�ۧN4���6��M9��U��ؽ?����uY�a	�Ȃ��1�A����.�L�<9|y�)t�z����=��FX�r�m�{�O�r��
5�%i2��1���R���U�ȉ@u����T��͂v�rk��ZP�� ���"�	 P�J��x�o�<���\-:��Θud��&��1�y�H�C�3�q��ᕴ؍ۨU;�	��ʙ����H�ȥ�ݸ&�t���V[�_��9J��F��,&C�8u*��������X����#��f���g��������ǛM��ǚ;����n�����	_�~����<��n������ڃ/�a������1k�w�OX�5VXs�3j���j�j���Wx��M�{qR���ͣm#���s7�� ��H}5��]+t�����]ѥKeo��8����}���&N�n�"b0��q�˅��������"�?̼��>X6�!0o�? 1[l��OC�	��3`���26pl�MP��Kz�E�)t��YO|�;"��m�.�:�b3(z悙�AP���6����j��|>�z ��SPN��wxn�-�
�h ۠�.�O�C���t�,)�Pv8�N6�mħ�;�fD& h��i{�`�@�\8�;h:�i���l��cpVP5�aH��ퟠh�������������['>d}g��H��:4cpQ��gy�N�
g���{�7 ����z����N��x?��%��S7l��ML=%�a�D����8"3�S�DCq�[�P
N�Y�s�66ٙ�4N�^o0�%�W�	9�[���(�qL}dGEP���h:2q���4����5o�~+ �E_uTx�
0�Яvñ5��Y4#��)�(0l�r��ш��/֜�{5˝ݣ:�	{+th᫣��޳�/�Ov^^�vߙ2lX��66+�l����{?�S�/w��`�j��/ ��w��؅�h0���c}q�p�Iw�ށ���%d͈�=y�
��q�7޸r�˚��deJ�z��y�t���O='Zה�d���w�$�ӆΘ%�$�5�C}G%��Ø9�PA��A;2wԑx�.�>�uF��ͯF�&M��{^]�黉�O�P�>"i+2nC9c"�R��I�{5N��q$��35�����Ya�E��r��B�g�����@q�	RRy	Wt\q�n�
~��WZ�_��f�Q[�m�-�l��	L9̔�.��s89�7�77��H~�/R����y1���'MDlxk�;\��.�ĤVh~FS/��(�@ɀ����I(��6���b�P�R���6#�Cʌ�6�"�@CE��*k�l�2��W�et���Z)FY�O��@� ј�$)�v>��uJW��տa�=֡\h�{P�B#�@]��ǆ�~%���(��d�W��@�������D��'L���7�>O�6���{3�W	0�,�|Ǫ*�*.I�&�o���ut���i������AC1+�~%V���߃ʝ޼'�4�jJ0�e|��� |����o�w�;w���r 	�M�.�D.��k�쓨��@Q4t���)���u��
'e�+���c:�쯮�X�r�(�n���L��;��X�w���D�4�����g���W�� �E�Dd>N�X�P�Z�1iz��ԛ�H�Շ9G�}]��1��A�e�j���0A�dU����$�kr������D�����r�.��(����R�D/�I�m=�p��/�fh6����"���=��4���?��A�|��D��%R�_A"�4	�*�6ۨ��3I'����\�?Z]��m]x(����1����O1U���~�{�ŧ!���wU��F$��6]�M��k�Sg￫r�:	�U�P/�9�4$��7:Q����Ov��2�*�����
[V��?J����g@!�j�����x�����W?O�>oZ����pM�\�&P�`؞����8�68�cK���ǳv��:h�B���@����\�˦����_��樻�{��x#���T�ߐ�`�6�<�]���M�FZ��;8^W��B&��s�#��ςM���F��zɱ	��j���h!�:�K����k�[��,�ųx��Y<�g�,�ųx��Y<�g�,�ųx��Y<��?��zi @ 