"""Synchronize eLinx and analysis project source lists with rtl/*.v."""
from pathlib import Path
import xml.etree.ElementTree as ET
import re
ROOT=Path(__file__).resolve().parents[1]
def main():
    names=sorted(p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').glob('*.v'))
    names.append('aihw_plugin/rtl/afdx_ai_tcn_plugin.v')
    path=ROOT/'ARINC.epr';tree=ET.parse(path)
    sources=tree.find(".//FileSet[@Type='DesignSrcs']")
    if sources is None:raise ValueError('Design source file set missing')
    for child in list(sources):
        if child.tag=='File':sources.remove(child)
    for name in names:ET.SubElement(sources,'File',Path='/'+name)
    ET.indent(tree,space='  ')
    tree.write(path,encoding='utf-8',xml_declaration=True)
    path=ROOT/'ARINC.qsf';lines=path.read_text(encoding='utf-8-sig').splitlines()
    lines=[s for s in lines if not re.search(r'-name\s+VERILOG_FILE\b',s)]
    lines += ['set_global_assignment -name VERILOG_FILE "'+name+'"' for name in names]
    path.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('PROJECT_SOURCES',len(names))
if __name__=='__main__':main()
