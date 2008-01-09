"======================================================================
|
|   GDBM declarations
|
|
 ======================================================================"


"======================================================================
|
| Copyright 2001 Free Software Foundation, Inc.
| Written by Steve Byrne.
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



CObject variableWordSubclass: #GDBM
	instanceVariableNames: ''
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Examples-Modules'
!
    
CStruct subclass: #DatumStruct
	declaration: #(		"typedef struct {	"
	    (#dPtr (#ptr #char))"	char *dptr;	"
	    (#dSize #long)	"	int   dsize;	"
	)			"      } datum;		"
	classVariableNames: ''
	poolDictionaries: ''
	category: 'Examples-GDBM'
!


!DatumStruct class methodsFor: 'instance creation'!

fromString: aString
    | obj strObj len |
    obj := self new.
    len := aString size.
    obj dSize value: len.
    obj dPtr value: (aString asCData: CCharType).
    obj addToBeFinalized.
    ^obj
! !


!DatumStruct methodsFor: 'accessing'!

asString
    | len ptr str |
    len := self dSize value.
    ptr := self dPtr value.
    str := String new: len.
    1 to: len do: 
	[ :i | str at: i put: (ptr at: i - 1) ].
    ^str
!

free
    self dPtr value free.
    super free
! !



"     GDBM_FILE gdbm_open(name, block_size, flags, mode, fatal_func);	"

GDBM class
	defineCFunc: 'gdbm_open'
	withSelectorArgs: 'open: fileName blockSize: size flags: flags
                            mode: modeInt fatalFunc: funcAddr'
	returning: GDBM type
	args: #(#string #int #int #int #cObject)
!

"     void gdbm_close(dbf);						"

GDBM
	defineCFunc: 'gdbm_close'
	withSelectorArgs: 'close'
	returning: #int
	args: #(#self)
!

"     int gdbm_store(dbf, key, content, flag);				"

GDBM
	defineCFunc: 'gdbm_store'
	withSelectorArgs: 'at: key put: value flag: aFlag' 
	returning: #int
	args: #(#self #cObject #cObject #int)
!

"     datum gdbm_fetch(dbf, key);					"

GDBM
	defineCFunc: 'gdbm_fetch'
	withSelectorArgs: 'at: key' 
	returning: DatumStruct type
	args: #(#self #cObject)
!

"     int gdbm_delete(dbf, key);					"

GDBM
	defineCFunc: 'gdbm_delete'
	withSelectorArgs: 'removeKey: key' 
	returning: #long
	args: #(#self #cObject)
!

"     datum gdbm_firstkey(dbf);						"

GDBM
	defineCFunc: 'gdbm_firstkey'
	withSelectorArgs: 'firstKey' 
	returning: DatumStruct type
	args: #(#self)
!

"     datum gdbm_nextkey(dbf, key);					"

GDBM
	defineCFunc: 'gdbm_nextkey'
	withSelectorArgs: 'nextKey: afterDatum' 
	returning: DatumStruct type
	args: #(#self #cObject)
!

"     int gdbm_reorganize(dbf);						"

GDBM
	defineCFunc: 'gdbm_reorganize'
	withSelectorArgs: 'reorganize'
	returning: #int
	args: #(#self)
!

!GDBM class methodsFor: 'testing'!

test
    | database key value |
    database := self open: 'test.gdbm' blockSize: 1024 flags: 2 "write/create"
		    mode: 8r666 fatalFunc: nil.

    key := DatumStruct fromString: 'fred'.
    value := DatumStruct fromString: 'Fred Flintstone'.
    database at: key put: value flag: 1 "replace".
    key free.
    value free.

    key := DatumStruct fromString: 'wilma'.
    value := DatumStruct fromString: 'Wilma Flintstone'.
    database at: key put: value flag: 1 "replace".
    key free.
    value free.

    database close.

    database := self open: 'test.gdbm' blockSize: 1024 flags: 0 "read"
		    mode: 8r666 fatalFunc: nil.

    value := (database at: (DatumStruct fromString: 'wilma')).
    value asString printNl.
    value free.

    value := (database at: (DatumStruct fromString: 'barney')).
    value asString printNl.
    value free.

    database close.
!

test2
    | database newItem item value |
    database := self open: 'test.gdbm' blockSize: 1024 flags: 0 "read"
		     mode: 8r666 fatalFunc: nil.

    item := database firstKey.
    [ item dPtr value notNil ] 
	whileTrue: [
	    value := database at: item.
	    Transcript nextPutAll: item asString;
		nextPutAll: '  ';
		nextPutAll: value asString;
		nl.

	    value free.

	    newItem := database nextKey: item.
	    item free.
	    item := newItem ].

    item free.
    database close.
!

test3
    | database newItem item value |
    database := self open: 'test.gdbm' blockSize: 1024 flags: 0 "read"
		     mode: 8r666 fatalFunc: nil.

    item := database firstKey.
    [ item dPtr value notNil ] 
	whileTrue: [
	    Transcript nextPutAll: item asString;
		nextPutAll: '  '.

	    newItem := database nextKey: item.
	    Transcript
		display: (newItem dPtr value
		    ifNotNil: [ :ignored | newItem asString ]);
		nl.
	    item free.
	    item := newItem ].

    item free.
    database close.
! !
