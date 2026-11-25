// Make a test copy of a zText module with another compression and/or a cipher key,
// using the real libsword classes, to check the Pascal reader against Sword itself.
//   mkmod <module data dir> <out data dir> <zip|lzss|bzip2> [cipherkey]
// build: g++ -I/usr/local/include/sword tools/mkmod.cpp -L/usr/local/lib -lsword -lbz2 -o build/mkmod
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <zipcomprs.h>
#include <lzsscomprs.h>
#include <bzlib.h>
#include <swcipher.h>
using namespace sword;

static std::vector<char> slurp(const std::string &f) {
	std::vector<char> v; FILE *fp = fopen(f.c_str(), "rb"); if (!fp) return v;
	char b[65536]; size_t n; while ((n = fread(b, 1, sizeof b, fp)) > 0) v.insert(v.end(), b, b + n);
	fclose(fp); return v;
}
static void spit(const std::string &f, const char *d, size_t n) {
	FILE *fp = fopen(f.c_str(), "wb"); fwrite(d, 1, n, fp); fclose(fp);
}
int main(int argc, char **argv) {
	if (argc < 4) return 1;
	std::string in = argv[1], out = argv[2], kind = argv[3];
	SWCipher *cipher = (argc > 4) ? new SWCipher((unsigned char *)argv[4]) : 0;
	for (const char *t : {"ot", "nt"}) {
		std::vector<char> bzs = slurp(in + "/" + t + ".bzs"), bzz = slurp(in + "/" + t + ".bzz");
		std::vector<char> bzv = slurp(in + "/" + t + ".bzv");
		if (bzs.empty()) continue;
		std::vector<char> nz, ns;
		for (size_t i = 0; i + 12 <= bzs.size(); i += 12) {
			unsigned int off, csz, usz;
			memcpy(&off, &bzs[i], 4); memcpy(&csz, &bzs[i + 4], 4); memcpy(&usz, &bzs[i + 8], 4);
			ZipCompress zc;
			unsigned long l = csz;
			zc.setCompressedBuf(&l, &bzz[off]);
			unsigned long ul = 0;
			char *u = zc.getUncompressedBuf(&ul);
			std::string data(u, ul);
			std::string zs;
			if (kind == "bzip2") {          // libsword here has no Bzip2Compress: plain libbz2, same format
				unsigned int bl = ul + ul / 50 + 600;
				std::vector<char> bb(bl);
				BZ2_bzBuffToBuffCompress(bb.data(), &bl, (char *)data.data(), ul, 6, 0, 0);
				zs.assign(bb.data(), bl);
			}
			else {
				SWCompress *nc = kind == "lzss" ? (SWCompress *)new LZSSCompress() : (SWCompress *)new ZipCompress();
				unsigned long ul2 = ul;
				nc->setUncompressedBuf(data.c_str(), &ul2);
				unsigned long zl = 0;
				char *z = nc->getCompressedBuf(&zl);
				zs.assign(z, zl);
				delete nc;
			}
			if (cipher) {
				cipher->setUncipheredBuf(zs.data(), zs.size());
				unsigned long cl = 0;
				char *c = cipher->getCipheredBuf(&cl);
				zs.assign(c, cl);
			}
			unsigned int noff = nz.size(), ncsz = zs.size(), nusz = ul;
			nz.insert(nz.end(), zs.begin(), zs.end());
			ns.insert(ns.end(), (char *)&noff, (char *)&noff + 4);
			ns.insert(ns.end(), (char *)&ncsz, (char *)&ncsz + 4);
			ns.insert(ns.end(), (char *)&nusz, (char *)&nusz + 4);
		}
		spit(out + "/" + t + ".bzs", ns.data(), ns.size());
		spit(out + "/" + t + ".bzz", nz.data(), nz.size());
		spit(out + "/" + t + ".bzv", bzv.data(), bzv.size());
	}
	return 0;
}
