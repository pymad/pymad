#-------------------------------------------------------------------------------
# This file is part of PyMad.
# 
# Copyright (c) 2011, CERN. All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
# 	http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#-------------------------------------------------------------------------------

#cython: embedsignature=True

'''
.. module:: madx
.. moduleauthor:: Yngve Inntjore Levinsen <Yngve.Inntjore.Levinsen.at.cern.ch>

Main module to interface with Mad-X library.

'''

from cern.libmadx.madx_structures cimport sequence_list, name_list
cdef extern from "madX/mad_api.h":
    sequence_list *madextern_get_sequence_list()
    #table *getTable()
cdef extern from "madX/mad_core.h":
    void madx_start()
    void madx_finish()

cdef extern from "madX/mad_str.h":
    void stolower_nq(char*)
cdef extern from "madX/mad_eval.h":
    void pro_input(char*)

cdef madx_input(char* cmd):
    stolower_nq(cmd)
    pro_input(cmd)

import os,sys
import cern.pymad.globals
from cern.libmadx import _madx_tools

_madstarted=False

# I think this is deprecated..
_loaded_models=[]

class madx:
    '''
    Python class which interfaces to Mad-X library
    '''
    def __init__(self,histfile='',recursive_history=False):
        '''
        Initializing Mad-X instance
        
        :param str histfile: (optional) name of file which will contain all Mad-X commands.
        :param bool recursive_history: If true, history file will contain no calls to other files. 
                                       Instead, recursively writing commands from these files when called.
        
        '''
        global _madstarted
        if not _madstarted:
            madx_start()
            _madstarted=True
        if histfile:
            self._hist=True
            self._hfile=file(histfile,'w')
            self._rechist=recursive_history
        elif cern.pymad.globals.MAD_HISTORY_BASE:
            base=cern.pymad.globals.MAD_HISTORY_BASE
            self._hist=True
            i=0
            while os.path.isfile(base+str(i)+'.madx'):
                i+=1
            self._hfile=file(base+str(i)+'.madx','w')
            self._rechist=recursive_history
        else:
            self._hist=False
            if recursive_history:
                print("WARNING: you cannot get recursive history without history file...")
            self._rechist=False
    
    def __del__(self):
        '''
         Closes history file
         madx_finish should
         not be called since
         other objects might still be
         running..
        '''
        if self._rechist:
            self._hfile.close()
        #madx_finish()
    
    # give lowercase version of command here..
    def _checkCommand(self,cmd):
        if "stop;" in cmd or "exit;" in cmd:
            print("WARNING: found quit in command: "+cmd+"\n")
            print("Please use madx.finish() or just exit python (CTRL+D)")
            print("Command ignored")
            return False
        if cmd.split(',')>0 and "plot" in cmd.split(',')[0]:
            print("WARNING: Plot functionality does not work through pymadx")
            print("Command ignored")
            return False
        # All checks passed..
        return True

    def command(self,cmd):
        '''
         Send a general Mad-X command. 
         Some sanity checks are performed.
         
         :param string cmd: command
        '''
        cmd=_madx_tools._fixcmd(cmd)
        if type(cmd)==int: # means we should not execute command
            return cmd
        if type(cmd)==list:
            for c in cmd:
                self._single_cmd(c)
        else:
            self._single_cmd(cmd)
    
    def _single_cmd(self,cmd):    
        if self._hist:
            if cmd[-1]=='\n':
                self._writeHist(cmd)
            else:
                self._writeHist(cmd+'\n')
        if self._checkCommand(cmd.lower()):
            madx_input(cmd)
        return 0
    
    def help(self,cmd=''):
        if cmd:
            print("Information about command: "+cmd.strip())
            cmd='help,'+cmd
        else:
            cmd='help'
            print("Available commands in Mad-X: ")
        self.command(cmd)
    
    def call(self,filename):
        '''
         Call a file
         
         :param string filename: Name of input file to call
        '''
        fname=filename
        if not os.path.isfile(fname):
            fname=filename+'.madx'
        if not os.path.isfile(fname):
            fname=filename+'.mad'
        if not os.path.isfile(fname):
            print("ERROR: "+filename+" not found")
            return 1
        cmd='call,file="'+fname+'"'
        self.command(cmd)
    ##
    # @brief run select command for a flag..
    # @param flag [string] the flag to run select on
    # @param pattern [list] the new pattern
    # @param columns [list/string] the columns you want for the flag
    def select(self,flag,columns,pattern=[]):
        self.command('SELECT, FLAG='+flag+', CLEAR;')
        if type(columns)==list:
            clms=', '.join(columns)
        else:
            clms=columns
        self.command('SELECT, FLAG='+flag+', COLUMN='+clms+';')
        for p in pattern:
            self.command('SELECT, FLAG='+flag+', PATTERN='+p+';')
            
    def twiss(self,
              sequence,
              pattern=['full'],
              columns='name,s,betx,bety,x,y,dx,dy,px,py,mux,muy,l,k1l,angle,k2l',
              madrange='',
              fname='',
              retdict=False,
              betx=None,
              bety=None,
              alfx=None,
              alfy=None,
              twiss_init=None,
              use=True
              ):
        '''
            
            Runs select+use+twiss on the sequence selected
            
            :param string sequence: name of sequence
            :param string fname: name of file to store tfs table
            :param list pattern: pattern to include in table
            :param list/string columns: columns to include in table
            :param bool retdict: if true, returns tables as dictionary types
            :param dict twiss_init: dictionary of twiss initialization variables
            :param bool use: Call use before aperture.
        '''
        if fname:
            tmpfile=fname
        else:
            tmpfile='twiss.temp.tfs'
            i=0
            while os.path.isfile(tmpfile):
                tmpfile='twiss.'+str(i)+'.temp.tfs'
                i+=1
        self.select('twiss',pattern=pattern,columns=columns)
        self.command('set, format="12.6F";')
        if use:
            self.use(sequence)
        _tmpcmd='twiss, sequence='+sequence+','+_madx_tools._add_range(madrange)+' file="'+tmpfile+'"'
        for i_var,i_val in {'betx':betx,'bety':bety,'alfx':alfx,'alfy':alfy}.items():
            if i_val!=None:
                _tmpcmd+=','+i_var+'='+str(i_val)
        if twiss_init:
            for i_var,i_val in twiss_init.items():
                if i_var not in ['name','closed-orbit']:
                    if i_val==True:
                        _tmpcmd+=','+i_var
                    else:
                        _tmpcmd+=','+i_var+'='+str(i_val)
        self.command(_tmpcmd+';')
        tab,param=_madx_tools._get_dict(tmpfile,retdict)
        if not fname:
            os.remove(tmpfile)
        return tab,param
    
    def survey(self,
              sequence,
              pattern=['full'],
              columns='name,l,s,angle,x,y,z,theta',
              madrange='',
              fname='',
              retdict=False,
              use=True
              ):
        '''
            Runs select+use+survey on the sequence selected
            
            :param string sequence: name of sequence
            :param string fname: name of file to store tfs table
            :param list pattern: pattern to include in table
            :param string/list columns: Columns to include in table
            :param bool use: Call use before survey.
        '''
        if fname:
            tmpfile=fname
        else:
            tmpfile='survey.temp.tfs'
            i=0
            while os.path.isfile(tmpfile):
                tmpfile='survey.'+str(i)+'.temp.tfs'
                i+=1
        self.select('survey',pattern=pattern,columns=columns)
        self.command('set, format="12.6F";')
        if use:
            self.use(sequence)
        self.command('survey,'+_madx_tools._add_range(madrange)+' file="'+tmpfile+'";')
        tab,param=_madx_tools._get_dict(tmpfile,retdict)
        if not fname:
            os.remove(tmpfile)
        return tab,param
            
    def aperture(self,
              sequence,
              pattern=['full'],
              madrange='',
              columns='name,l,angle,x,y,z,theta',
              offsets='',
              fname='',
              retdict=False,
              use=False
              ):
        '''
         Runs select+use+aperture on the sequence selected
         
         @param sequence [string] name of sequence
         @param fname [string,optional] name of file to store tfs table
         @param pattern [list, optional] pattern to include in table
         @param columns [string or list, optional] columns to include in table
         :param bool use: Call use before aperture.
        '''
        if fname:
            tmpfile=fname
        else:
            tmpfile='aperture.temp.tfs'
            i=0
            while os.path.isfile(tmpfile):
                tmpfile='aperture.'+str(i)+'.temp.tfs'
                i+=1
        self.select('aperture',pattern=pattern,columns=columns)
        self.command('set, format="12.6F";')
        if use:
            print "Warning, use before aperture is known to cause problems"
            self.use(sequence) # this seems to cause a bug?
        self.command('aperture,'+_madx_tools._add_range(madrange)+_madx_tools._add_offsets(offsets)+'file="'+tmpfile+'";')
        tab,param=_madx_tools._get_dict(tmpfile,retdict)
        if not fname:
            os.remove(tmpfile)
        return tab,param
        
    def use(self,sequence):
        self.command('use, sequence='+sequence+';')

    # turn on/off verbose outupt..
    def verbose(self,switch):
        if switch:
            self.command("option, echo, warn, info")
        else:
            self.command("option, -echo, -warn, -info")

    def _writeHist(self,command):
        # this still brakes for "multiline commands"...
        if self._rechist and command.split(',')[0].strip().lower()=='call':
            cfile=command.split(',')[1].strip().strip('file=').strip('FILE=').strip(';\n').strip('"').strip("'")
            if sys.flags.debug:
                print("DBG: call file ",cfile)
            fin=file(cfile,'r')
            for l in fin:
                self._writeHist(l+'\n')
        else:
            self._hfile.write(command)
            self._hfile.flush()
    
    def get_sequences(self):
        '''
         Returns the sequences currently in memory
        '''
        cdef sequence_list *seqs
        seqs= madextern_get_sequence_list()
        ret={}
        for i in xrange(seqs.curr):
            ret[seqs.sequs[i].name]={'name':seqs.sequs[i].name}
            if seqs.sequs[i].tw_table.name is not NULL:
                ret[seqs.sequs[i].name]['twissname']=seqs.sequs[i].tw_table.name
                print "Table name:",seqs.sequs[i].tw_table.name
                print "Number of columns:",seqs.sequs[i].tw_table.num_cols
                print "Number of columns (orig):",seqs.sequs[i].tw_table.org_cols
                print "Number of rows:",seqs.sequs[i].tw_table.curr
        return ret
        #print "Currently number of sequenses available:",seqs.curr
        #print "Name of list:",seqs.name