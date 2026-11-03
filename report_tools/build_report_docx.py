"""Generate a technical review from an explicit actual run, never fixed verdicts."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def build(run,output,template=None):
    from docx import Document
    from docx.shared import Pt
    run=Path(run).resolve();output=Path(output).resolve()
    if output.exists():raise FileExistsError(output)
    result=json.loads((run/'acceptance.json').read_text(encoding='utf-8'))
    hashes=json.loads((run/'source_hashes.json').read_text(encoding='utf-8'))
    changed=[n for n,h in hashes.items() if not (ROOT/n).is_file() or hashlib.sha256((ROOT/n).read_bytes()).hexdigest()!=h]
    doc=Document(str(template)) if template else Document()
    doc.add_heading('AFDX 工程验证记录',0)
    doc.add_paragraph('结果来自明确指定的真实运行。功能测试不等同于全标准认证。')
    doc.add_paragraph('运行目录：'+str(run))
    doc.add_paragraph('完成时间：'+str(result.get('finished_at','未记录')))
    doc.add_paragraph('功能状态：'+str(result.get('functional_status','未知')))
    doc.add_paragraph('当前源码相对运行输入变化文件数：'+str(len(changed)))
    if changed:doc.add_paragraph('本记录是历史运行，不能证明当前源码通过。')
    rows=result.get('tests',[])
    doc.add_paragraph(f"实际用例：{len(rows)}；PASS：{sum(r.get('status')=='PASS' for r in rows)}")
    table=doc.add_table(rows=1,cols=3)
    for cell,value in zip(table.rows[0].cells,('用例','状态','原始日志')):cell.text=value
    for row in rows:
        for cell,value in zip(table.add_row().cells,(row['name'],row['status'],row.get('log',''))):cell.text=str(value)
    doc.add_heading('工具阶段',1)
    doc.add_paragraph(json.dumps(result.get('elinx',{}),ensure_ascii=False,indent=2))
    doc.add_heading('实现与验证范围',1)
    for name in ('docs/REVIEW_20261103.md','docs/DOWNLOAD_615A.md'):
        text=(ROOT/name).read_text(encoding='utf-8')
        for line in text.splitlines():
            if line.strip():doc.add_paragraph(line)
    doc.add_heading('输入指纹',1)
    doc.add_paragraph('source_hashes.json SHA-256：'+hashlib.sha256((run/'source_hashes.json').read_bytes()).hexdigest())
    output.parent.mkdir(parents=True,exist_ok=True)
    doc.save(output)
    return output


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--template',type=Path)
    args=p.parse_args();print(build(args.run,args.output,args.template))


if __name__=='__main__':main()
