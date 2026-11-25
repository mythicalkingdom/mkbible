Unit MKBibBok;       {Abstract Book Object (interface only so far)}

{$I MKBib.Def}

{
  MKBibBok - AbsBookObj: general books, a tree of titled sections (theWord .gbk.twm books, Sword
  GenBook modules, the books of a STEP / WORDsearch library).  Nodes are numbered 1..GetNodeCount;
  node 0 is the root (the book itself), which has no text of its own.

  Only the interface exists; a descendant for a format is still to be written.
}

Interface

Uses MKBibMod;

Type
  AbsBookObj = Object(AbsModObj)
  Function  GetNodeCount: LongInt; Virtual;
  Function  GetFirstChild(Node: LongInt): LongInt; Virtual; {0 = none}
  Function  GetNextSibling(Node: LongInt): LongInt; Virtual;
  Function  GetParent(Node: LongInt): LongInt; Virtual; {0 = the root}
  Function  GetNodeTitle(Node: LongInt): BibStr; Virtual;
  Function  GetNodeText(Node: LongInt): BibStr; Virtual; {markup as stored}
  Function  GetNodePath(Node: LongInt): BibStr; Virtual; {titles from the root, separated by /}
  Function  FindNode(Const Path: BibStr): LongInt; Virtual; {0 = not found}
  Function  AddNode(Parent: LongInt; Const Title, Txt: BibStr): LongInt; Virtual; {writing: the new node, 0 = failed}
  End;

Type AbsBookPtr = ^AbsBookObj;

Implementation

Function AbsBookObj.GetNodeCount: LongInt;
  Begin
  GetNodeCount := 0;
  End;

Function AbsBookObj.GetFirstChild(Node: LongInt): LongInt;
  Begin
  GetFirstChild := 0;
  End;

Function AbsBookObj.GetNextSibling(Node: LongInt): LongInt;
  Begin
  GetNextSibling := 0;
  End;

Function AbsBookObj.GetParent(Node: LongInt): LongInt;
  Begin
  GetParent := 0;
  End;

Function AbsBookObj.GetNodeTitle(Node: LongInt): BibStr;
  Begin
  GetNodeTitle := '';
  End;

Function AbsBookObj.GetNodeText(Node: LongInt): BibStr;
  Begin
  GetNodeText := '';
  End;

Function AbsBookObj.GetNodePath(Node: LongInt): BibStr;
  Var R: BibStr;
  Begin
  R := '';
  While Node > 0 Do
    Begin
    If R = '' Then R := GetNodeTitle(Node) Else R := GetNodeTitle(Node) + '/' + R;
    Node := GetParent(Node);
    End;
  GetNodePath := R;
  End;

Function AbsBookObj.FindNode(Const Path: BibStr): LongInt;
  Var i: LongInt;
  Begin
  FindNode := 0;
  For i := 1 To GetNodeCount Do
    If GetNodePath(i) = Path Then
      Begin
      FindNode := i;
      Exit;
      End;
  End;

Function AbsBookObj.AddNode(Parent: LongInt; Const Title, Txt: BibStr): LongInt;
  Begin
  AddNode := 0;
  End;

End.
