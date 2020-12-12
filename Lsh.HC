#define LAMBDA_BITMAP 0x006336363C181B0E
#define LAMBDA "\xFB"
#define LAMBDA_CHARCODE 0xFB

#define MAX_LINE_LEN	255
#define AUTOCOMPLETE_MAX_RESULTS 15

#define HIST_FILE_PATH		"~/LshHistory.TXT.Z"
#define HIST_MAX_ENTRIES	300

// -------------------------------------
// History
/*
$TR,"History overview"$
$ID,2$Command history is stored as pointers to MAlloc'd
strings in a circular buffer. This allows for efficient
pushing of new entries, as well as simple freeing of
old entries.

A new entry is added right-to-left. The oldest entry is
freed and then replaced with the new. The head is
decremented, wrapping around to the top of the buffer
when needed.

History is saved to/loaded from HIST_FILE_PATH, newest
commands last.

$ID,-2$$TR,"Relative history"$
$ID,2$When a user has a partial string in their line buff, up/down
will jump to the next/prev entry that starts with that
substring using a linear search.

Since moving up/down in history will necessarily replace the
current line buffer, the `seek_str` stores the line buffer any
time a character is typed or on backspace. It's reset after
pushing history or resetting the line with esc.

$ID,-2$*/

Bool IsPureWhitespace(U8 *str) {
  I64 i;

  for (i=0; i<StrLen(str); i++) {
    switch (str[i]) {
      case CH_SPACE:
      case CH_SHIFT_SPACE:
      case '\t':
        break;
      default:
        return FALSE;
    }
  }
  return TRUE;
}

Bool StrStartsWith(U8 *str, U8 *substr) {
  // Str starts with substr but not the same str.
  // Returns TRUE if substr is empty str.

  I64 i;
  for (i=0; substr[i] != \0; i++) {
    if (str[i] != substr[i])
      return FALSE;
  }

  // Same len = same str.
  if (str[i] == \0) {
    return FALSE;
  } else {
    return TRUE;
  }
}

I64 WrapI64(I64 n, I64 max) {
  // Wraps `n` around zero and `max`.
  return ((n % max) + max) % max;
}

class History {
  I64 index;	// Temp index for user.
  I64 head;	// Start of circular buff.
  I64 used;	// Elements filled.
  U8 *buff[HIST_MAX_ENTRIES];
  U8 seek_str[MAX_LINE_LEN+1];
};

U8 *HistoryGet(History *h, I64 index) {
  // Get history at index relative to head.

  if (index == -1)
    return "";

  I64 i = WrapI64(h->head + index, HIST_MAX_ENTRIES);

  return h->buff[i];
}

U0 HistoryResetCursor(History *h) {
  h->index = -1;
  h->seek_str[0] = \0;
}

U0 HistoryPush(History *h, U8 *line) {
  // Push entry and update history.

  if (line[0] != NULL
    && !IsPureWhitespace(line)
    && StrCmp(line, HistoryGet(h, 0))
    && StrLen(line) < MAX_LINE_LEN) {

    I64 final_index = WrapI64(h->head - 1, HIST_MAX_ENTRIES);

    // Free last entry in queue before it's overwritten.
    // NULL is freeable in HolyC.
    Free(h->buff[final_index]);

    // Update head and used, then push entry.
    h->used = ClampI64(h->used+1, 0, HIST_MAX_ENTRIES);
    h->head = final_index;
    h->buff[h->head] = MAlloc(StrLen(line)+1);
    StrCpy(h->buff[h->head], line);

  }
  HistoryResetCursor(h);
}

U0 HistoryInit(History *h) {
  // Init history and load old entries if available.

  I64 i;
  h->index = -1;
  h->head = 0;
  h->used = 0;

  MemSet(h->seek_str, 0, (MAX_LINE_LEN+1)*sizeof(U8));
  MemSet(h->buff, 0, HIST_MAX_ENTRIES*sizeof(I64));

  // Load previous history.
  if (FileFind(HIST_FILE_PATH)) {
    U8 *prev_hist = FileRead(HIST_FILE_PATH);
    U8 line[MAX_LINE_LEN+1];
    MemSet(line, 0, sizeof(line));

    I64 last_newline_index = 0;

    for (i=0; i<StrLen(prev_hist); i++) {
      if (prev_hist[i] == '\n' || prev_hist[i+1] == \0) {
          last_newline_index = i + 1;
          HistoryPush(h, line);
          MemSet(line, 0, sizeof(line));
      } else {
          line[i-last_newline_index] = prev_hist[i];
      }
    }
  }
}

U0 HistorySave(History *h) {
  // Save history to disk. Newest commands last.

  I64 i;

  // Get len for `str_buff`. Save room for newlines and \0.
  I64 str_buff_len = 1;
  for (i=0; i<h->used; i++) {
    str_buff_len += StrLen(HistoryGet(h, i)) + 1;
  }

  // Build str.
  U8 *str_buff = CAlloc(str_buff_len * sizeof(U8));
  for (i=0; i<h->used; i++) {
    U8 *entry = HistoryGet(h, h->used-(i+1));
    StrPrint(str_buff, "%s%s\n", str_buff, entry);
  }

  FileWrite(HIST_FILE_PATH, str_buff, str_buff_len);
  Free(str_buff);
}

U0 HistoryFree(History *h) {
  // Free history buffer.
  // NULL ptrs are freeable in HolyC.

  I64 i;
  for (i=0; i<HIST_MAX_ENTRIES; i++) {
    Free(h->buff[i]);
  }
}

U8 *HistoryCycle(History *h, U8 *line, Bool reverse=FALSE) {
  // Moves up/down in history. If there's a non-empty str
  // in `h->seek_str`, it jumps to the next/prev entry that
  // starts with that substr.
  // Sets hist index and returns command upon matching.

  I64 i;
  U8 *entry;

  if (!reverse) {
    for (i=h->index+1; i<h->used; i++) {
      entry = HistoryGet(h, i);
      if (StrStartsWith(entry, h->seek_str)
          && StrCmp(entry, line)) {
        h->index = i;
        return entry;
      }
    }
    // No entries match.
    return line;

  } else {
    for (i=h->index-1; i>=0; i--) {
      entry = HistoryGet(h, i);
      if (StrStartsWith(entry, h->seek_str)
          && StrCmp(entry, line)) {
        h->index = i;
        return entry;
      }
    }
    // No entries match.
    h->index = -1;
    return h->seek_str;
  }
}

// -------------------------------------
// Line input

U8* ReadLine(U8* prompt, I64 (*autocomplete)(U8* buffer) = NULL,
	History *history) {
  static U8 buf[MAX_LINE_LEN+1];
  I64 len = 0;

  buf[0] = 0;

show_prompt:
  DocBottom;
  "" prompt;
  "" buf;

  while (len < MAX_LINE_LEN) {
    I64 scan;
    I64 ch = GetKey(&scan, FALSE, FALSE);

    if (ch == CH_BACKSPACE) {
      if (len > 0) {
        '' CH_BACKSPACE;
        --len;

        buf[len] = \0;
        StrCpy(history->seek_str, buf);
      }
    }
    else if (ch == CH_ESC) {
      len = 0;
      buf[len] = \0;
      HistoryResetCursor(history);
      EdLineDel(DocPut);
      goto show_prompt;
    }
    else if (ch == CH_SHIFT_ESC) {
      return 0;
    }
    else if (ch == '\t' && autocomplete) {
      buf[len] = \0;

      // Completing path or last argument?
      U8* start = StrLastOcc(buf, " ");

      if (start)
        start++;
      else
        start = buf;

      // Find matching results
      I64 results = autocomplete(start);
      len = StrLen(buf);

      // If multiple results were printed,
      // we need to wait for the WinMgr (or whoever)
      // to catch up. UGH!
      if (results > 1)
        Sleep(200);

      EdLineDel(DocPut);
      goto show_prompt;
    }
    else if (ch == 0) {
      Bool reverse;
      I64 move_index_num;

      if (scan.u8[0] == SC_CURSOR_UP) {
        reverse = FALSE;
        move_index_num = 1;
      }
      else if (scan.u8[0] == SC_CURSOR_DOWN) {
        reverse = TRUE;
        move_index_num = -1;
      }
      else {
        goto skip;
      }

      buf[len] = \0;
      StrCpy(buf, HistoryCycle(history, buf, reverse));

      len = StrLen(buf);
      EdLineDel(DocPut);
      goto show_prompt;
      skip:
    }
    else if (ch) {
      '' ch;

      if (ch == '\n')
        break;

      buf[len++] = ch;
      buf[len] = \0; //Make buf a string

      StrCpy(history->seek_str, buf);
    }
  }

  buf[len] = \0;
  return buf;
}

// -------------------------------------
// Parse

I64 Tokenize(U8* str, U8** tokens) {
  I64 count = 0;
  Bool started = FALSE;

  while (*str) {
    if (*str == ' ' || *str == CH_SHIFT_SPACE) {
      if (started) {
        *str = 0;
        started = FALSE;
      }
    }
    else if (!started) {
      tokens[count] = str;
      count++;
      started = TRUE;
    }

    str++;
  }

  return count;
}

U0 TransformCommand(U8* command, U8* exec_buf) {
  Bool upperize = TRUE;
  I64 pos = 0;

  for (; *command; command++) {
    if (*command == '-')
      upperize = TRUE;
    else if (upperize) {
      exec_buf[pos++] = ToUpper(*command);
      upperize = FALSE;
    }
    else
      exec_buf[pos++] = *command;
  }

  exec_buf[pos] = 0;
}

// -------------------------------------
// Autocomplete

class CHashTableIter {
  CHashTable* ht;
  I64 i;
  CHash* curr;
  I64 recursive;
};

U0 HashTableIterBegin(CHashTableIter* it, CHashTable* ht, I64 recursive) {
  it->ht = ht;
  it->i = 0;
  it->curr = NULL;
  it->recursive = recursive;
}

CHash* HashTableIterNext(CHashTableIter* it) {
  // End of current bucket?
  while (!it->curr) {
    // End of hash table?
    while (it->i >= it->ht->mask) {
      // If recursive search is enabled,
      // jump to the next table in chain
      if (it->recursive) {
        if (!it->ht->next)
          return NULL;

        it->ht = it->ht->next;
        it->i = 0;
      }
      else
        return NULL;
    }

    it->curr = it->ht->body[it->i];
    it->i++;
  }

  CHash* ret = it->curr;
  it->curr = it->curr->next;
  return ret;
}

class CAutocompleteIter {
  U8* query;
  I64 length;
  CDirEntry* entries;
  CDirEntry* de;
  CHashTableIter hti;
};

class CAutocompleteResult {
  // Exactly one of these will be set
  CDirEntry* de;
  CHashFun* fun;
};

U0 AutocompleteIterRewind(CAutocompleteIter* it) {
  it->de = it->entries;
  HashTableIterBegin(&it->hti, Fs->hash_table, TRUE);
}

U0 AutocompleteIterBegin(CAutocompleteIter* it, U8* query) {
  it->query = query;
  it->length = StrLen(query);

  U8* mask = MStrPrint("%s*", query);
  try {
    it->entries = FilesFind(mask);
  }
  catch {
    it->entries = NULL;
  }
  Free(mask);

  AutocompleteIterRewind(it);
}

I64 AutocompleteIterNext(CAutocompleteIter* it, CAutocompleteResult* out) {
  // Go through all file matches first
  while (it->de) {
    if (it->de->name[0] != '.') {
      // Return the DE, iteration will resume at the next one
      out->de = it->de;
      out->fun = NULL;
      it->de = it->de->next;
      return TRUE;
    }

    it->de = it->de->next;
  }

  // Go through all hashtable matches
  CHash* next;
  while ((next = HashTableIterNext(&it->hti))) {
    // Function?
    if ((next->type & HTT_FUN) != 0
        && !StrNICmp(next->str, it->query, it->length)) {
      out->de = NULL;
      out->fun = next(CHashFun*);
      return TRUE;
    }
  }

  return FALSE;
}

U0 AutocompleteIterEnd(CAutocompleteIter* it) {
  DirTreeDel(it->entries);
}

U0 AutocompleteSetResult(U8* buffer, U8* str, I64 length) {
  // Completing path or last argument?
  U8* start = StrLastOcc(buffer, "/");

  if (start)
    start++;
  else
    start = buffer;

  MemCpy(start, str, length);
  start[length] = 0;
}

I64 StrCommonSubset(U8* a, U8* b) {
  I64 len = 0;
  while (*a && *b == *a) {
    a++;
    b++;
    len++;
  }
  return len;
}

// No matches -> return 0
// 1 match -> return 1, set *p_match to alloced
// multiple matches -> print matches, return count
I64 Autocomplete(U8* buffer) {
  // This is somewhat complicated, because we want
  // to avoid any unnecessary allocations.

  CAutocompleteIter it;
  CAutocompleteResult first, next;

  AutocompleteIterBegin(&it, buffer);

  if (!AutocompleteIterNext(&it, &first)) {
    // No results.
    return 0;
  }

  I64 count;
  U8* str;

  if (!AutocompleteIterNext(&it, &next)) {
    // Single result.

    if (first.de)
      str = first.de->name;
    else if (first.fun)
      str = first.fun->str;

    AutocompleteSetResult(buffer, str, StrLen(str));

    count = 1;
  }
  else {
    U8* common_base = NULL;
    I64 common_length = 0;

    AutocompleteIterRewind(&it);

    count = 0;
    "\n";

    while (count < AUTOCOMPLETE_MAX_RESULTS
        && AutocompleteIterNext(&it, &next)) {
      if (next.de) {
        str = next.de->name;
        "$FG,4$%s\n", str;
      }
      else if (next.fun) {
        str = next.fun->str;
        "$FG,3$%s\n", str;
      }

      if (!common_base) {
        common_base = str;
        common_length = StrLen(common_base);
      }
      else {
        I64 new_common = StrCommonSubset(common_base, str);
        if (common_length > new_common)
          common_length = new_common;
      }

      count++;
    }

    if (AutocompleteIterNext(&it, &next))
      "$FG,6$Too many results, display truncated\n$FG$";
    else if (common_length > StrLen(buffer))
      AutocompleteSetResult(buffer, common_base, common_length);
  }

  AutocompleteIterEnd(&it);
  return count;
}

// -------------------------------------
// Shell

Bool skip_intro = FALSE;

U8* DirCurShort() {
  U8* dir = DirCur();
  // FIXME!!
  if (!StrCmp(dir, "C:/Home")) {
    Free(dir);
    return StrNew("~");
  }
  else
    return dir;
}

CHashFun* FindFunction(U8* name) {
  CHash* result = HashFind(name, Fs->hash_table, HTT_FUN);

  if (result && (result->type & HTT_FUN) != 0)
    return result(CHashFun *);
  else
    return NULL;
}

Bool IsPath(U8* str) {
  for (; *str; str++) {
    if (*str == '/')
      return TRUE;
  }

  return FALSE;
}

U8* Prompt() {
  // TODO: Avoid malloc if we can rely on MAX_PATH
  static U8 buf[200];
  U8* dir = DirCurShort();

  //StrPrint(buf, "$FG,5$" LAMBDA " $FG,8$%s $FG,0$", dir);
  StrPrint(buf, "$FG,8$%s $FG,5$" LAMBDA " $FG,0$", dir);
  Free(dir);
  return buf;
}

U0 PatchFont() {
  U64* font = sys_font_std;
  font[LAMBDA_CHARCODE] = LAMBDA_BITMAP;
}

// -------------------------------------
// Main

U0 Intro() {
  "\n"
  "$FG,1$- #include files by absolute or relative path\n"
  "  $FG,7$" LAMBDA "$FG,0$ ./Lsh $FG,7$=> #include \"Lsh\"\n"
  "\n"
  "$FG,1$- Call functions\n"
  "  $FG,7$" LAMBDA "$FG,0$ cd .. $FG,7$=> Cd(\"..\");\n"
  "  $FG,7$" LAMBDA "$FG,0$ dir $FG,7$=> Dir;\n"
  "  $FG,7$" LAMBDA "$FG,0$ ed Program.HC $FG,7$=> Ed(\"Program.HC\");\n"
  "  $FG,7$" LAMBDA "$FG,0$ file-mgr $FG,7$=> FileMgr;\n"
  "\n"
  "$FG,1$- Execute code directly\n"
  "  $FG,7$" LAMBDA "$FG,0$ 'DskChg('B');\n"
  "\n"
  "$FG,1$- $FG,0$Esc$FG,1$ deletes line\n"
  "$FG,1$- $FG,0$Tab$FG,1$ auto-completes paths\n"
  "$FG,1$- $FG,0$Shift-Esc$FG,1$ quits\n"
  "$FG,1$- $FG,0$Up/Down Arrows$FG,1$ cycle through previous commands\n"
  "\n";
}

U0 ParseAndExecute(U8* line) {
  if (line[0] == '#')
    return;

  if (line[0] == '\'') {
    ExePutS(line + 1);
    return;
  }

  U8* tokens[10];
  I64 count = Tokenize(line, tokens);

  if (count) {
    if (IsPath(tokens[0])) {
      "$FG$";
      ExePrint("#include \"%s\";", tokens[0]);
    }
    else {
      U8 exec_buf[200];

      TransformCommand(tokens[0], exec_buf);
      CHashFun* fun = FindFunction(exec_buf);

      if (!fun) {
        "%s: $FG,4$function not found$FG$\n", exec_buf;
        return;
      }

      if (count > 1) {
        CatPrint(exec_buf, "(");
        I64 have;
        for (have = 1; have < count; have++) {
          if (have > 1)
            CatPrint(exec_buf, ",");

          CatPrint(exec_buf, "\"%s\"", tokens[have]);
        }
        CatPrint(exec_buf, ")");
      }
      CatPrint(exec_buf, ";");
      "$FG,7$%s\n$FG$", exec_buf;
      ExePutS(exec_buf);
    }
  }
}

U0 Lsh() {
  PatchFont();

  History history;
  HistoryInit(&history);

  if (!skip_intro) {
    "$FG,8$Welcome to $FG,5$Lambda Shell$FG,8$!\n";
    "Type $FG,0$intro$FG,8$ for a quick introduction.\n\n";
  }

  while (1) {
    U8* p = Prompt();
    U8* line = ReadLine(p, &Autocomplete, &history);

    if (!line || !StrCmp(line, "exit"))
      break;

    HistoryPush(&history, line);

    try {
      ParseAndExecute(line);
    }
    catch {
      PutExcept();
    }
  }
  HistorySave(&history);
  HistoryFree(&history);
  "$FG$\n";
}
