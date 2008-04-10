"======================================================================
|
|   Smalltalk in Smalltalk compiler
|
|
 ======================================================================"


"======================================================================
|
| Copyright 1999, 2000, 2001, 2002 Free Software Foundation, Inc.
| Written by Paolo Bonzini.
|
| This file is part of GNU Smalltalk.
|
| GNU Smalltalk is free software; you can redistribute it and/or modify it
| under the terms of the GNU General Public License as published by the Free
| Software Foundation; either version 2, or (at your option) any later version.
| 
| GNU Smalltalk is distributed in the hope that it will be useful, but WITHOUT
| ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
| FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
| details.
| 
| You should have received a copy of the GNU General Public License along with
| GNU Smalltalk; see the file COPYING.  If not, write to the Free Software
| Foundation, 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.  
|
 ======================================================================"


RBProgramNodeVisitor subclass: #STFakeCompiler
       instanceVariableNames: ''
       classVariableNames: ''
       poolDictionaries: 'VMOtherConstants VMByteCodeNames'
       category: 'System-Compiler'
! 

STFakeCompiler comment:
'I am the Smalltalk equivalent of a wimp. I never do nothing: they tell me
to compile something, and I just return nil...

Actually, I am used when conditionally compiled code has to be skipped.'!

!STFakeCompiler class methodsFor: 'evaluation'!

evaluate: aSequenceNode parser: aParser
    ^nil
! !

!STFakeCompiler class methodsFor: 'compilation'!

compile: methodDefNode for: aBehavior classified: aString parser: aParser
    ^nil
! !

STFakeCompiler subclass: #STCompiler
       instanceVariableNames: 'node symTable parser bytecodes depth maxDepth isInsideBlock dupReceiver'
       classVariableNames: 'OneNode TrueNode FalseNode NilNode SuperVariable SelfVariable ThisContextVariable DoitToken'
       poolDictionaries: ''
       category: 'System-Compiler'
! 

STCompiler comment:
'Unlike my brother STFakeCompiler, I am a real worker. Give me some nodes, and
I will output a full-fledged CompiledMethod!!

Compilation takes place as a visit of a tree of RBParseNodes, through the
Visitor pattern embodied by the superclass RBParseNodeVisitor.  For
example, when we send the ''true printOn: stdout'' message, the structure
of the tree is:

    RBMessageNode, which contains:
	the receiver, a RBLiteralNode
	the message, a RBMessageNode, which contains
	     the selector
	     the arguments, a Collection which contains a RBVariableNode

#acceptMessageNode: checks if the receiver is super. If so, it tells the message
to compile itself as a send to super. In this case however it tells both the
receiver and the message to compile themselves.
#acceptLiteralNode: will output a ''push true'' bytecode.
#acceptMessageNode:, in turn, asks the parameters to compile themselves, asks
the STSymTable object to add the #printOn: literal, then compiles a ''send
message'' bytecode.
The RBVariableNode which refers to stdout, when it is asked to compile itself,
tells the STCompiler object to add a literal (since it refers to a global
variable) and then compiles either a ''push global variable'' or a ''push
indexed'' bytecode. The resulting stream is

	push true
	push literal corresponding to (#stdout -> stdout)
	send message with 0 args, selector = #printOn:'!

!STCompiler class methodsFor: 'initialize'!

initialize
    OneNode := RBLiteralNode value: 1.
    TrueNode := RBLiteralNode value: true.
    FalseNode := RBLiteralNode value: false.
    NilNode := RBLiteralNode value: nil.
    SelfVariable := RBVariableNode named: 'self'.
    SuperVariable := RBVariableNode named: 'super'.
    ThisContextVariable := RBVariableNode named: 'thisContext'! !

!STCompiler class methodsFor: 'evaluation'!

evaluate: aSequenceNode parser: aParser
    | cm methodNode |
    aSequenceNode addReturn.
    methodNode := RBMethodNode new
	arguments: #();
	body: aSequenceNode;
	selector: #Doit;
	source: nil;
	yourself.

    cm := self new
	class: UndefinedObject parser: aParser;
	visitNode: methodNode.

    ^nil perform: cm
! !

!STCompiler class methodsFor: 'compilation'!

compile: methodNode for: aBehavior classified: aString parser: aParser
    | cm |
    cm := self new
	class: aBehavior parser: aParser;
	visitNode: methodNode.

    cm methodCategory: aString.

    ^aBehavior
	addSelector: methodNode selector
	withMethod: cm
!

compile: methodNode asMethodOf: aBehavior classified: aString parser: aParser
    | cm |
    cm := self new
	class: aBehavior parser: aParser;
	visitNode: methodNode.

    cm methodCategory: aString.

    ^cm
! !

!STCompiler methodsFor: 'private'!

class: aBehavior parser: aParser
    symTable := STSymbolTable new.
    parser := aParser.
    bytecodes := WriteStream on: (ByteArray new: 240).
    dupReceiver := false.
    isInsideBlock := 0.

    symTable declareEnvironment: aBehavior.
! !


!STCompiler methodsFor: 'accessing'!

addLiteral: literal
    ^symTable addLiteral: literal
!

bytecodesFor: aBlockNode
    ^self bytecodesFor: aBlockNode atEndDo: []
!

bytecodesFor: aBlockNode atEndDo: aBlock
    | saveBytecodes result |
    saveBytecodes := bytecodes.
    bytecodes := WriteStream on: (ByteArray new: 240).
    self declareArgumentsAndTemporaries: aBlockNode.
    self compileStatements: aBlockNode body.
    self undeclareArgumentsAndTemporaries: aBlockNode.
    aBlock value.

    result := bytecodes contents.
    bytecodes := saveBytecodes.
    ^result
!

checkStore: aVariableName
    (symTable canStore: aVariableName) ifFalse: [
	self compileError: 'cannot store in argument ', aVariableName
    ]
!

compileError: aString
    parser parserError: aString
!

compileBackJump: displacement
    | jumpLen |
    jumpLen := displacement + 2.
    jumpLen := displacement + (self sizeOfJump: jumpLen).
    jumpLen := displacement + (self sizeOfJump: jumpLen).
    self compileByte: JumpBack arg: displacement
!

compileJump: displacement if: jmpCondition
    displacement < 0 ifTrue: [
	 "Should not happen"
	 ^self error: 'Cannot compile backwards conditional jumps'.
    ].
    self depthDecr: 1.
    jmpCondition
	ifFalse: [ self compileByte: PopJumpFalse arg: displacement ]
	ifTrue: [ self compileByte: PopJumpTrue arg: displacement ].
!

compileWarning: aString
    parser parserWarning: aString
!

declareTemporaries: node
    node temporaries do: [ :aTemp |
	symTable
	    declareTemporary: aTemp name
	    canStore: true
	    for: self
    ].
!

declareArgumentsAndTemporaries: node
    node arguments do: [ :anArg |
	symTable
	    declareTemporary: anArg name
	    canStore: false
	    for: self
    ].
    self declareTemporaries: node body
!

maxDepth
    ^maxDepth
!

depthDecr: n
    depth := depth - n
!

depthIncr
    depth = maxDepth
	ifTrue: [ depth := depth + 1. maxDepth := maxDepth + 1 ]
	ifFalse: [ depth := depth + 1 ]
!

depthSet: n
    "n can be an integer, or a previously returned value (in which case the
     exact status at the moment of the previous call is remembered)"
    | oldDepth |
    oldDepth := n -> maxDepth.
    n isInteger
	ifTrue: [ depth := maxDepth := n ]
	ifFalse: [ depth := n key. maxDepth := n value ].
    ^oldDepth
!

literals
    ^symTable literals
!

lookupName: variable
    | definition |
    definition := symTable lookupName: variable for: self.

    definition isNil ifTrue: [
	"Might want to declare this puppy as a local and go on
	 notwithstanding the error"

	 self compileError: 'Undefined variable ', 
	     variable printString, ' referenced.'
    ].
    ^definition
!

compileByte: aByte
    self compileByte: aByte arg: 0.
!

compileByte: aByte arg: arg
    | n |
    n := 0.
    [ (arg bitShift: n) > 255 ] whileTrue: [ n := n - 8 ].
    n to: -8 by: 8 do: [ :shift |
	bytecodes
	    nextPut: ExtByte;
	    nextPut: ((arg bitShift: shift) bitAnd: 255).
    ].
    bytecodes
	nextPut: aByte;
	nextPut: (arg bitAnd: 255)
!

compileByte: aByte arg: arg1 arg: arg2
    self compileByte: aByte arg: (arg1 bitShift: 8) + arg2
!

nextPutAll: aByteArray
    bytecodes nextPutAll: aByteArray.
!

isInsideBlock
    ^isInsideBlock > 0
!

pushLiteral: value
    | definition |
    (value isInteger and: [ value >= 0 and: [ value <= 16r3FFFFFFF ]])
	    ifTrue: [ self compileByte: PushInteger arg: value. ^self ].

    definition := self addLiteral: value.
    self compileByte: PushLitConstant arg: definition
!

pushLiteralVariable: value
    | definition |
    definition := self addLiteral: value.
    self compileByte: PushLitVariable arg: definition
!

sizeOfJump: distance
    distance < 256 ifTrue: [ ^2 ].
    distance < 65536 ifTrue: [ ^4 ].
    distance < 16777216 ifTrue: [ ^6 ].
    ^8
!

displacementsToJumpAround: jumpAroundOfs and: initialCondLen
    | jumpAroundLen oldJumpAroundLen finalJumpOfs finalJumpLen |
    jumpAroundLen := oldJumpAroundLen := 0.
    [
	finalJumpOfs := initialCondLen + oldJumpAroundLen + jumpAroundOfs.
	finalJumpLen := self sizeOfJump: finalJumpOfs.
	jumpAroundLen := self sizeOfJump: jumpAroundOfs + finalJumpLen.
	oldJumpAroundLen = jumpAroundLen
    ]   whileFalse: [
	oldJumpAroundLen := jumpAroundLen
    ].

    ^(finalJumpLen + finalJumpOfs) -> (jumpAroundOfs + finalJumpLen)
!

insideNewScopeDo: aBlock
    | result |
    isInsideBlock := isInsideBlock + 1.
    symTable scopeEnter.
    result := aBlock value.
    symTable scopeLeave.
    isInsideBlock := isInsideBlock - 1.
    ^result
!

bindingOf: anOrderedCollection
    | binding |
    binding := symTable bindingOf: anOrderedCollection for: self.
    binding isNil ifTrue: [
	 self compileError: 'Undefined variable binding', 
	     anOrderedCollection asArray printString, 'referenced.'
    ].
    ^binding
!

undeclareTemporaries: aNode
    aNode temporaries do: [ :each | symTable undeclareTemporary: each name ].
!

undeclareArgumentsAndTemporaries: aNode
    self undeclareTemporaries: aNode body.
    aNode arguments do: [ :each | symTable undeclareTemporary: each name ]
! !

!STCompiler methodsFor: 'visiting RBSequenceNodes'!

acceptSequenceNode: node
    | statements method |
    node addSelfReturn.
    depth := maxDepth := 0.
    self declareTemporaries: node.
    self compileStatements: node.
    self undeclareTemporaries: node.
    symTable finish.

    method := CompiledMethod
	literals: symTable literals
	numArgs: 0
	numTemps: symTable numTemps
	attributes: #()
	bytecodes: bytecodes contents
	depth: maxDepth + symTable numTemps.

    method descriptor
	setSourceCode: node source;
	methodClass: UndefinedObject;
	selector: #executeStatements.

    ^method
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBMethodNodes'!

acceptMethodNode: node
    | statements method |
    node body addSelfReturn.

    depth := maxDepth := 0.

    self declareArgumentsAndTemporaries: node.
    self compileStatements: node body.
    self undeclareArgumentsAndTemporaries: node.
    symTable finish.

    method := CompiledMethod
	literals: symTable literals
	numArgs: node arguments size
	numTemps: node body temporaries size
	attributes: #()
	bytecodes: bytecodes contents
	depth: maxDepth + node body temporaries size + node arguments size.

    method descriptor
	setSourceCode: node source;
	methodClass: symTable environment;
	selector: node selector.

    ^method
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBArrayConstructorNodes'!

acceptArrayConstructorNode: aNode
    "STArrayNode is the parse node class for {...} style array constructors.
     It is compiled like a normal inlined block, but with the statements
     preceded by (Array new: <size of the array>) and with each statement
     followed with a <pop into instance variable of new stack top>
     instead of a simple pop."

    self
	depthIncr;
	pushLiteralVariable: (Smalltalk associationAt: #Array);
	depthIncr;
	compileByte: PushInteger arg: aNode body statements size;
	depthDecr: 1;
	compileByte: SendImmediate arg: NewColonSpecial.

    aNode body statements keysAndValuesDo: [ :index :each |
	each acceptVisitor: self.
	self
	    depthDecr: 1;
	    compileByte: PopStoreIntoArray arg: index.
    ]
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBBlockNodes'!

acceptBlockNode: aNode
    "STBlockNode has a variable that contains a string for each parameter,
     and one that contains a list of statements. Here is how STBlockNodes
     are compiled:

	push BlockClosure or CompiledBlock literal
	make dirty block                    <--- only if pushed CompiledBlock

     Statements are put in a separate CompiledBlock object that is referenced
     by the BlockClosure that the sequence above pushes or creates.

     compileStatements: creates the bytecodes.  It is this method that is
     called by STCompiler>>bytecodesFor: and STCompiler>>bytecodesFor:append:"

    | bc depth block clean |
    depth := self depthSet: aNode arguments size + aNode body temporaries size.
   
    aNode body statements isEmpty ifTrue: [
	aNode body addNode: (RBLiteralNode value: nil).
    ].
 
    bc := self insideNewScopeDo: [
	self bytecodesFor: aNode atEndDo: [
	    aNode body lastIsReturn
		ifFalse: [ self compileByte: ReturnContextStackTop ]
	]
    ].

    block := CompiledBlock
	numArgs: aNode arguments size
	numTemps: aNode body temporaries size
	bytecodes: bc
	depth: self maxDepth
	literals: self literals.

    self depthSet: depth.

    clean := block flags.
    clean == 0 ifTrue: [
        self pushLiteral: (BlockClosure
	    block: block
	    receiver: symTable environment).

        ^aNode ].

    self pushLiteral: block.
    self compileByte: MakeDirtyBlock
!

compileStatements: aNode
    aNode statements keysAndValuesDo: [ :index :each |
	index = 1 ifFalse: [
	    self
		depthDecr: 1;
		compileByte: PopStackTop
	].
	each acceptVisitor: self.
    ].
    aNode statements isEmpty ifTrue: [
	self
	    depthIncr;
	    compileByte: PushSpecial arg: NilIndex
    ].
! !


"--------------------------------------------------------------------"
!STCompiler methodsFor: 'visiting RBCascadeNodes'!

acceptCascadeNode: aNode
    "RBCascadeNode holds a collection with one item per message."

    | messages first |
    messages := aNode messages.
    first := messages at: 1.
    first receiver = SuperVariable ifTrue: [
	aNode messages
	    do: [ :each | self compileSendToSuper: each ]
	    separatedBy: [ self depthDecr: 1; compileByte: PopStackTop ].

	^aNode
    ].

    dupReceiver := true.
    first acceptVisitor: self.

    messages
	from: 2 to: messages size - 1
	do: [ :each |
	    self compileByte: PopStackTop; compileByte: DupStackTop.
	    each acceptVisitor: self ].

    self compileByte: PopStackTop.
    self depthDecr: 1.
    (messages at: messages size) acceptVisitor: self.
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBOptimizedNodes'!

acceptOptimizedNode: aNode
    self depthIncr.

    self pushLiteral: (self class evaluate: aNode body parser: parser)
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBLiteralNodes'!

acceptLiteralNode: aNode
    "STLiteralNode has one instance variable, the token for the literal
     it represents."
    self depthIncr.

    aNode compiler: self.
    self pushLiteral: aNode value.
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBAssignmentNodes'!

acceptAssignmentNode: aNode
    "First compile the assigned, then the assignment to the assignee..."
    aNode value acceptVisitor: self.
    (VMSpecialIdentifiers includesKey: aNode variable name)
	ifTrue: [
	    self compileError: 'cannot assign to ', aNode variable name
	].

    self compileAssignmentFor: aNode variable.
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'compiling'!

acceptMessageNode: aNode
    "RBMessageNode contains a message send. Its instance variable are
     a receiver, selector, and arguments."
    | dup specialSelector args litIndex |

    dup := dupReceiver. dupReceiver := false.
 
    aNode receiver = SuperVariable ifTrue: [
	self compileSendToSuper: aNode.
	^true
    ].

    (VMSpecialMethods includesKey: aNode selector) ifTrue: [
	specialSelector := VMSpecialMethods at: aNode selector.
	(specialSelector isNil and: [aNode receiver isBlock and: [ dup not ]])
	    ifTrue: [
		(self compileWhileLoop: aNode) ifTrue: [^false]
	    ]
	].

    aNode receiver acceptVisitor: self.
    dup ifTrue: [ self depthIncr; compileByte: DupStackTop ].
    specialSelector isNil ifFalse: [
	(self perform: specialSelector with: aNode) ifTrue: [^false]
    ].

    aNode arguments do: [ :each | each acceptVisitor: self ].

    VMSpecialSelectors at: aNode selector ifPresent: [ :idx |
	idx <= LastImmediateSend
	    ifTrue: [ self compileByte: idx arg: 0 ]
	    ifFalse: [ self compileByte: SendImmediate arg: idx ].
	^aNode
    ].

    args := aNode arguments size.
    litIndex := self addLiteral: aNode selector.
    self compileByte: Send arg: litIndex arg: args.
!

compileWhileLoop: aNode
    "Answer whether the while loop can be optimized (that is,
     whether the only parameter is a STBlockNode)"

    | whileBytecodes argBytecodes jumpOffsets |

    (aNode receiver arguments isEmpty and: [
	aNode receiver body temporaries isEmpty ]) ifFalse: [ ^false ].

    argBytecodes := #().
    aNode arguments do: [ :onlyArgument |
	onlyArgument isBlock ifFalse: [ ^false ].
        (onlyArgument arguments isEmpty and: [
	    onlyArgument body temporaries isEmpty ])
		ifFalse: [ ^false ].

	argBytecodes := self bytecodesFor: onlyArgument atEndDo: [
	    self compileByte: PopStackTop; depthDecr: 1 ]
    ].
    whileBytecodes := self bytecodesFor: aNode receiver.
    self nextPutAll: whileBytecodes.

    aNode selector == #repeat
	ifFalse: [
            jumpOffsets := self
		displacementsToJumpAround: argBytecodes size
		and: whileBytecodes size + 2.   "for jump around jump"

	    "The if: clause means: if selector is whileFalse:, compile
	     a 'pop/jump if true'; else compile a 'pop/jump if false'"
	    self
		compileJump: (self sizeOfJump: jumpOffsets value)
	        if: (aNode selector == #whileTrue or: [ aNode selector == #whileTrue: ]).

	    self
	        compileByte: Jump
	        arg: jumpOffsets value.

	    argBytecodes isNil ifFalse: [
	        self nextPutAll: argBytecodes
	    ].

	    self
		compileByte: JumpBack
		arg: jumpOffsets key
        ]
	ifTrue: [
	    self compileBackJump: whileBytecodes size
	].

    "Somebody might want to use the return value of #whileTrue:
     and #whileFalse:"

    self depthIncr; compileByte: PushSpecial arg: NilIndex.
    ^true
!

compileSendToSuper: aNode
    | litIndex args |
    self depthIncr; compileByte: PushSelf.
    aNode arguments do: [ :each | each acceptVisitor: self ].
    VMSpecialSelectors at: aNode selector ifPresent: [ :idx |
	self compileByte: SendSuperImmediate arg: idx.
	^aNode
    ].

    litIndex := self addLiteral: aNode selector.
    args := aNode arguments size.
    self compileByte: SendSuper arg: litIndex arg: args.
    self depthDecr: aNode arguments size.
!

compileTimesRepeat: aNode
    | block |
    block := aNode arguments first.
    (block arguments isEmpty and: [
	block body temporaries isEmpty ]) ifFalse: [ ^false ].

    ^false
!

compileLoop: aNode
    | stop step block |
    aNode arguments do: [ :each |
	stop := step.			"to:"
	step := block.			"by:"
	block := each.			"do:"
    ].
    (block arguments size = 1 and: [
	block body temporaries isEmpty ]) ifFalse: [ ^false ].

    stop isNil
	ifTrue: [ stop := step. step := OneNode ]	"#to:do:"
	ifFalse: [ step isImmediate ifFalse: [ ^false ] ].

    ^false
!

compileBoolean: aNode
    | bc1 ret1 bc2 selector |
    aNode arguments do: [ :each |
        (each arguments isEmpty and: [
	    each body temporaries isEmpty ]) ifFalse: [ ^false ].

	bc1 isNil
	    ifTrue: [
		bc1 := self bytecodesFor: each.
		ret1 := each isReturn ]
	    ifFalse: [
		bc2 := self bytecodesFor: each ].
    ].

    selector := aNode selector.
    bc2 isNil ifTrue: [
	"Transform everything into #ifTrue:ifFalse: or #ifFalse:ifTrue:"

	selector == #ifTrue: ifTrue: [
	    selector := #ifTrue:ifFalse: . bc2 := NilIndex. "Push nil"
	].
	selector == #ifFalse: ifTrue: [
	    selector := #ifFalse:ifTrue: . bc2 := NilIndex. "Push nil"
	].
	selector == #and: ifTrue: [
	    selector := #ifTrue:ifFalse: . bc2 := FalseIndex. "Push false"
	].
	selector == #or: ifTrue: [
	    selector := #ifFalse:ifTrue: . bc2 := TrueIndex. "Push true"
	].
	bc2 := { PushSpecial. bc2 }.
	^self compileBoolean: aNode
	    longBranch: bc1 returns: ret1 shortBranch: bc2
	    longIfTrue: selector == #ifTrue:ifFalse:
    ].

    selector == #ifTrue:ifFalse: ifTrue: [
	^self compileIfTrue: bc1 returns: ret1 ifFalse: bc2
    ].
    selector == #ifFalse:ifTrue: ifTrue: [
	^self compileIfFalse: bc1 returns: ret1 ifTrue: bc2
    ].
    ^false "What happened?!?"
!

compileBoolean: aNode longBranch: bc1 returns: ret1 shortBranch: bc2
	longIfTrue: longIfTrue

    self
	compileJump: bc1 size + (ret1 ifTrue: [ 0 ] ifFalse: [ 2 ])
	if: longIfTrue not.

    self nextPutAll: bc1.
    ret1 ifFalse: [
	self compileByte: Jump arg: bc2 size.
    ].
    self nextPutAll: bc2.
    ^true
!

compileIfTrue: bcTrue returns: bcTrueReturns ifFalse: bcFalse

    | trueSize |
    trueSize := bcTrueReturns
	ifTrue: [ bcTrue size ]
	ifFalse: [ bcTrue size + (self sizeOfJump: bcFalse size) ].

    self compileJump: trueSize if: false.
    self nextPutAll: bcTrue.
    bcTrueReturns ifFalse: [
	self compileByte: Jump arg: bcFalse size.
    ].
    self nextPutAll: bcFalse.
    ^true
!

compileIfFalse: bcFalse returns: bcFalseReturns ifTrue: bcTrue

    | falseSize |
    falseSize := bcFalseReturns
	ifTrue: [ bcFalse size ]
	ifFalse: [ bcFalse size + (self sizeOfJump: bcTrue size) ].

    self compileJump: falseSize if: true.
    self nextPutAll: bcFalse.
    bcFalseReturns ifFalse: [
	self compileByte: Jump arg: bcFalse size.
    ].
    self nextPutAll: bcTrue.
    ^true
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'compiling'!

acceptReturnNode: aNode
    aNode value acceptVisitor: self.
    self isInsideBlock
	ifTrue: [ self compileByte: ReturnMethodStackTop ]
	ifFalse: [ self compileByte: ReturnContextStackTop ]
! !

"--------------------------------------------------------------------"

!STCompiler methodsFor: 'visiting RBVariableNodes'!

compileAssignmentFor: aNode
    "RBVariableNode has one instance variable, the name of the variable
     that it represents."
    | definition |

    self checkStore: aNode name.
    definition := self lookupName: aNode name.

    (symTable isTemporary: aNode name) ifTrue: [
	^self
	    compileStoreTemporary: definition
	    scopes: (symTable outerScopes: aNode name)
    ].    

    (symTable isReceiver: aNode name) ifTrue: [
	^self compileByte: StoreReceiverVariable arg: definition.
    ].
    
    ^self compileByte: StoreLitVariable arg: definition.
!

acceptVariableNode: aNode
    | locationType definition |

    self depthIncr.
    VMSpecialIdentifiers at: aNode name ifPresent: [ :block |
	block value: self.
	^aNode
    ].

    definition := self lookupName: aNode name.

    (symTable isTemporary: aNode name) ifTrue: [
	^self
	    compilePushTemporary: definition
	    scopes: (symTable outerScopes: aNode name)
    ].    
    (symTable isReceiver: aNode name) ifTrue: [
	self compileByte: PushReceiverVariable arg: definition.
	^aNode
    ].
    
    self
	compileByte: PushLitVariable arg: definition.
!

compilePushTemporary: number scopes: outerScopes
    outerScopes = 0 ifFalse: [
	self
	    compileByte: PushOuterVariable
	    arg: number
	    arg: outerScopes.
	^self
    ].
    self
	compileByte: PushTemporaryVariable
	arg: number
!

compileStoreTemporary: number scopes: outerScopes
    outerScopes = 0 ifFalse: [
	self
	    compileByte: StoreOuterVariable
	    arg: number
	    arg: outerScopes.
	^self
    ].
    self
	compileByte: StoreTemporaryVariable
	arg: number
! !

STCompiler initialize!