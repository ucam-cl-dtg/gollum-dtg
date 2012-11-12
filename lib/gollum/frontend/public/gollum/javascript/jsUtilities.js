/*------------------------------------------------------------------------------
Filename:       jsUtilities Library
Author:         Aaron Gustafson (aaron at easy-designs dot net)
                unless otherwise noted
Creation Date:  4 June 2005
Version:        2.1
Homepage:       http://www.easy-designs.net/code/jsUtilities/
License:        Creative Commons Attribution-ShareAlike 2.0 License
                http://creativecommons.org/licenses/by-sa/2.0/
Note:           If you change or improve on this script, please let us know by 
                emailing the author (above) with a link to your demo page.
------------------------------------------------------------------------------*/
function UinArray(needle) { for (var i=0; i < this.length; i++) { if (this[i] === needle) { return i; } } return false; }
function UaddClass(theClass) { if (this.className != '') { this.className += ' ' + theClass; } else { this.className = theClass; } }
function UlastChildContainingText() { var testChild = this.lastChild; var contentCntnr = ['p','li','dd']; while (testChild.nodeType != 1) { testChild = testChild.previousSibling; }  var tag = testChild.tagName.toLowerCase(); var tagInArr = UinArray.apply(contentCntnr, [tag]); if (!tagInArr && tagInArr!==0) { testChild = UlastChildContainingText.apply(testChild); } return testChild; }
