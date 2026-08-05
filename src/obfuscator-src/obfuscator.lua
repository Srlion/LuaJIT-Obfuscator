math.randomseed(tostring(function() end):sub(11))

local bit = require("bit")
local jit_util = require("jit.util")
local buffer = require("string.buffer")

local string = string
local math = math

local type = type
local setmetatable = setmetatable
local tostring = tostring
local tonumber = tonumber

local DEBUGGING = false

local OBFUSCATING_MODE = true

--
jit.opt.start(3)
jit.opt.start(
  "maxtrace=10000",
  "maxrecord=10000",
  "maxirconst=1000",
  "maxside=200",
  "maxsnap=1000",
  "hotloop=10",
  "hotexit=1",
  "tryside=10",
  "instunroll=8",
  "loopunroll=25",
  "callunroll=5",
  "recunroll=4",
  "sizemcode=64",
  "maxmcode=2048"
)
--

local BC_NAMES = {}; do
    local bcnames = "ISLT  ISGE  ISLE  ISGT  ISEQV ISNEV ISEQS ISNES ISEQN ISNEN ISEQP ISNEP ISTC  ISFC  IST   ISF   ISTYPEISNUM MOV   NOT   UNM   LEN   ADDVN SUBVN MULVN DIVVN MODVN ADDNV SUBNV MULNV DIVNV MODNV ADDVV SUBVV MULVV DIVVV MODVV POW   CAT   KSTR  KCDATAKSHORTKNUM  KPRI  KNIL  UGET  USETV USETS USETN USETP UCLO  FNEW  TNEW  TDUP  GGET  GSET  TGETV TGETS TGETB TGETR TSETV TSETS TSETB TSETM TSETR CALLM CALL  CALLMTCALLT ITERC ITERN VARG  ISNEXTRETM  RET   RET0  RET1  FORI  JFORI FORL  IFORL JFORL ITERL IITERLJITERLLOOP  ILOOP JLOOP JMP   FUNCF IFUNCFJFUNCFFUNCV IFUNCVJFUNCVFUNCC FUNCCW"
    for i = 0, #bcnames / 6 - 1 do
        local name = bcnames:sub(i * 6 + 1, i * 6 + 6):gsub(" ", "")
        BC_NAMES[i] = name
    end
end

local get_uv_info; do
    local PROTO_UV_LOCAL = 0x8000
    local PROTO_UV_IMMUTABLE = 0x4000
    local PROTO_UV_INDEX = 0x3FFF
    function get_uv_info(proto, idx)
        local uvinfo = jit_util.funcuv(proto, idx)
        local is_local = bit.band(uvinfo, PROTO_UV_LOCAL) ~= 0
        local is_immutable = bit.band(uvinfo, PROTO_UV_IMMUTABLE) ~= 0
        local slot_id = bit.band(uvinfo, PROTO_UV_INDEX)
        return {
            is_local = is_local,
            is_immutable = is_immutable,
            slot_id = slot_id,
            name = jit_util.funcuvname(proto, idx),
        }
    end
end

local GET_RANDOM_NAME; do
    local invs_chars = {
        "ˏ",
        "​",
        "​",
        "​",
        "​",
        "😶‍🌫️",
        "😎",
        "🥳",
        "🤡",
        "🕵️",
        "🧐",
        "😡",
        "💩",
        "🦾",
        "👀",
        "🫵🏽",
        "🐤",
        "🐰",
        "🐷",
        "🐭",
        "❄️",
        "🍉",
        "🦴",
        "🎱",
        "⚽️",
        "🎖",
        "🍪",
        "🍔",
        "🩻",
        "😵‍💫",
        "🫥",
        "🫠",
        "🙂‍↔️",
        "🙂‍↕️",
        "🔴",
        "🟠"
    }

    local USED_NAMES = {}
    local CACHED_IDS = {}

    local current_id = math.random(1, #invs_chars)
    local random_name = function()
        current_id = (current_id % #invs_chars) + 1
        return invs_chars[current_id]
    end

    function GET_RANDOM_NAME(id)
        if CACHED_IDS[id] then
            return CACHED_IDS[id]
        end

        local unique_name = ""
        repeat
            unique_name = unique_name .. random_name()
        until USED_NAMES[unique_name] == nil

        CACHED_IDS[id] = unique_name
        USED_NAMES[unique_name] = true
        return unique_name
    end
end

local MINGE_STR

local METHODS = {}
local OPS = {}

-- to insert a jmp label at pc
local JMP_OPS = {
    JMP = true,
    FORI = true,
    FORL = true,
    ITERL = true,
    LOOP = true,
    UCLO = true,
    ISNEXT = true,
}

local function Obfuscator(proto, parent)
    local info = jit_util.funcinfo(proto)
    setmetatable(info, {__index = METHODS})

    info.proto = proto
    info.parent = parent
    info.id = parent and parent.id + 1 or 0
    info.buf = buffer.new(1024) -- Buffer to store the obfuscated code
    info.pc = -1

    local instructions = {}
    info.instructions = instructions

    local pc_labels = {}
    info.pc_labels = pc_labels

    for pc = 0, info.bytecodes - 1 do
        local ins = jit_util.funcbc(proto, pc)
        local op = bit.band(ins, 0xFF)
        local op_name = BC_NAMES[op] or "UNKNOWN"

        local a = bit.rshift(bit.band(ins, 0xFF00), 8)
        local b = bit.rshift(bit.band(ins, 0xFF000000), 24)
        local c = bit.rshift(bit.band(ins, 0xFF0000), 16)
        local d = bit.rshift(bit.band(ins, 0xFFFF0000), 16)

        if JMP_OPS[op_name] then
            pc_labels[info:GetJMPPos(pc, d)] = true
        end

        instructions[pc] = {
            ins = ins,
            pc = pc,
            op = op,
            op_name = op_name,
            a = a,
            b = b,
            c = c,
            d = d,
        }
    end

    local boxed = {}
    info.boxed = boxed
    for pc = 0, info.bytecodes - 1 do
        local ins = instructions[pc]
        if ins.op_name == "FNEW" then
            local childproto = jit_util.funck(proto, -ins.d - 1)
            local cinfo = jit_util.funcinfo(childproto)
            for uv = 0, cinfo.upvalues - 1 do
                local uvinfo = get_uv_info(childproto, uv)
                if uvinfo.is_local then
                    boxed[uvinfo.slot_id] = true
                end
            end
        end
    end

    info:Setup()

    return info
end

function METHODS:Write(str)
    self.buf:put(str)
end

function METHODS:Writef(fmt, ...)
    self.buf:putf(fmt, ...)
end

do
    local CURRENT_PARAMS
    local gsub_function = function(key)
        local value = CURRENT_PARAMS[key]
        if value == nil then
            value = CURRENT_PARAMS[tonumber(key)]
        end
        if value == nil then
            error("invalid key: " .. key)
        end
        return value
    end
    function METHODS:WriteP(str, params)
        CURRENT_PARAMS = params
        str = str:gsub("{([%w_]+)}", gsub_function)
        self:Write(str)
    end
end

function METHODS:GetNConst(d)
    local n_const = jit_util.funck(self.proto, d)
    n_const = self:Num(n_const)
    return n_const
end

function METHODS:GetGCConst(d)
    return (jit_util.funck(self.proto, -d - 1))
end

function METHODS:GetJMPPos(pc, d)
    return pc + d - 0x7fff
end

function METHODS:TablePackName()
    return self:Name("table_pack", true)
end

function METHODS:GetFuncName(name)
    return self:Name("const_func_" .. name, true)
end

function METHODS:Setup()
    -- Locals
    self:Writef("local %s={};", self:Name("locals"))
    -- Pre-create boxes for captured slots so writes to locals[i][1] are valid
    if self.boxed then
        for slot in pairs(self.boxed) do
            self:Writef("%s[%d]={};", self:Name("locals"), slot)
        end
    end
    -- Returns (CALL, CALLT, CALLM, CALLMT, VARG)
    self:Writef("local %s={};", self:Name("returns"))
    self:Writef("local %s=0;", self:Name("multires"))
    -- set it up only for the main function
    if not self.parent then
        -- Table Pack function
        self:Writef("local %s=function(...)return{...},select('#',...)end;", self:TablePackName())
        -- getfenv function
        self:Writef("local %s=getfenv;", self:GetFuncName("getfenv"))
        -- unpack function
        self:Writef("local %s=unpack;", self:GetFuncName("unpack"))
    end
    -- Varargs
    -- if not self.parent then
    --     self:WriteP("local {varargs},{varargs_n}={table_pack}(...);", {
    --         varargs = self:Name("varargs"),
    --         varargs_n = self:Name("varargs_n"),
    --         table_pack = self:TablePackName(),
    --     })
    -- end
end

function METHODS:Start()
    local instructions = self.instructions
    local count = #instructions
    while self.pc < count do
        self:Next()
    end
end

function METHODS:Next()
    self.pc = self.pc + 1

    local pc = self.pc
    local ins = self.instructions[pc]
    local op_name = ins.op_name
    if DEBUGGING then
        print("OPCODE: " .. op_name)
    end

    if self.pc_labels[pc] then
        self:Writef("::_%d_%d::", self.id, pc) -- label
    end

    local handler = OPS[op_name]
    if handler then
        self.current_ins = ins
        handler(self, ins.a, ins.b, ins.c, ins.d)
    else
        error("Unknown opcode: " .. op_name)
        print("Unknown opcode: " .. op_name)
    end
end

function METHODS:Name(key, no_id)
    if OBFUSCATING_MODE then
        if no_id then
            return GET_RANDOM_NAME(key)
        end
        return GET_RANDOM_NAME(self.id .. key)
    end
    if no_id then
        return "_" .. key
    end
    return "_" .. self.id .. key
end

function METHODS:IsBoxed(idx)
    -- only numeric stack slots can be captured/boxed
    return type(idx) == "number" and self.boxed and self.boxed[idx]
end

function METHODS:GetLocal(idx)
    local tpy = type(idx)
    if tpy == "number" or tpy == "boolean" then
        idx = idx -- do nothing
    elseif tpy == "string" then
        idx = "\"" .. idx .. "\""
        return self:Name("locals") .. "[" .. idx .. "]"
    else
        error("invalid index type: " .. tpy)
    end
    local base = self:Name("locals") .. "[" .. idx .. "]"
    if self:IsBoxed(idx) then
        return base .. "[1]"
    end
    return base
end

function METHODS:SetLocal(idx, val)
    val = tostring(val)
    self:Writef("%s=%s;", self:GetLocal(idx), val)
end

function METHODS:GetUV(idx)
    local uvinfo = get_uv_info(self.proto, idx)
    if uvinfo.is_local then
        local slot = uvinfo.slot_id
        if self.captured_boxes and self.captured_boxes[slot] then
            return self.captured_boxes[slot] .. "[1]"
        end
        return (self.parent:GetLocal(slot))
    end
    return (self.parent:GetUV(uvinfo.slot_id))
end

function METHODS:SetUV(idx, val)
    val = tostring(val)
    local uv_local = self:GetUV(idx)
    self:Writef("%s=%s;", uv_local, val)
end

function METHODS:Num(val)
    if val == 0 then
        return "0"
    elseif val ~= val then
        return "0/0"
    elseif val == math.huge then
        return "(999999e+999999)"
    end
    local num_str = string.format("%.17g", val)
    if tonumber(num_str) ~= val then -- just as a safety check
        error("failed to convert number to string: " .. val)
    end
    return num_str
end

function METHODS:Pri(val)
    if val == 1 or val == false then
        return "false"
    elseif val == 2 or val == true then
        return "true"
    elseif val == 0 then
        return "nil"
    end
    error("invalid PRI value: " .. val)
end

function METHODS:ToLuaVal(val, allow_nil)
    local tpy = type(val)
    if tpy == "string" then
        val = MINGE_STR(val)
        return val
    elseif tpy == "number" then
        return self:Num(val)
    elseif tpy == "boolean" then
        return self:Pri(val)
    elseif allow_nil and val == nil then
        return "nil"
    end
    error("invalid value type: " .. tpy)
end

function METHODS:Dump()
    return self.buf:tostring()
end

function METHODS:Print()
    print(self:Dump())
end

do
    -- Function Headers
    function OPS:FUNCF(a, b, c, d)
        for i = 0, self.params - 1 do
            self:SetLocal(i, self:Name("params" .. i))
        end
    end

    OPS.FUNCV = OPS.FUNCF
    -- End Function Headers

    -- Comparison Ops
    local function CompOP(self, var, op, val)
        var = self:GetLocal(var)
        self:WriteP("if({var}{op}{val})then ", {
            var = var,
            op = op,
            val = val,
        })
        -- all comparison ops have a jump after them, so execute the jump after the comparison and then close the if block
        self:Next()
        self:Write("end;")
    end

    -- if not (a > d) then
    function OPS:ISLT(a, b, c, d)
        CompOP(self, a, "<", self:GetLocal(d))
    end

    function OPS:ISGE(a, b, c, d)
        CompOP(self, a, ">=", self:GetLocal(d))
    end

    -- if not (a >= d) then
    function OPS:ISLE(a, b, c, d)
        CompOP(self, a, "<=", self:GetLocal(d))
    end

    function OPS:ISGT(a, b, c, d)
        CompOP(self, a, ">", self:GetLocal(d))
    end

    function OPS:ISEQV(a, b, c, d)
        CompOP(self, a, "==", self:GetLocal(d))
    end

    function OPS:ISNEV(a, b, c, d)
        CompOP(self, a, "~=", self:GetLocal(d))
    end

    function OPS:ISEQS(a, b, c, d)
        local const = self:GetGCConst(d)
        const = self:ToLuaVal(const)
        CompOP(self, a, "==", const)
    end

    function OPS:ISNES(a, b, c, d)
        local const = self:GetGCConst(d)
        const = self:ToLuaVal(const)
        CompOP(self, a, "~=", const)
    end

    function OPS:ISEQN(a, b, c, d)
        local const = self:GetNConst(d)
        CompOP(self, a, "==", const)
    end

    function OPS:ISNEN(a, b, c, d)
        local const = self:GetNConst(d)
        CompOP(self, a, "~=", const)
    end

    function OPS:ISEQP(a, b, c, d)
        d = self:Pri(d)
        CompOP(self, a, "==", d)
    end

    function OPS:ISNEP(a, b, c, d)
        d = self:Pri(d)
        CompOP(self, a, "~=", d)
    end
    -- End Comparison Ops

    -- Unary Test and Copy Ops
    function OPS:ISTC(a, b, c, d)
        -- Copy D to A and jump, if D is true
        self:WriteP("if({d})then {a}={d};", {
            a = self:GetLocal(a),
            d = self:GetLocal(d),
        })
        self:Next()
        self:Write("end;")
    end

    function OPS:ISFC(a, b, c, d)
        -- Copy D to A and jump, if D is false
        self:WriteP("if(not {d})then {a}={d};", {
            a = self:GetLocal(a),
            d = self:GetLocal(d),
        })
        self:Next()
        self:Write("end;")
    end

    function OPS:IST(a, b, c, d)
        -- Copy D to A and jump, if D is true
        self:WriteP("if({d})then ", {
            a = self:GetLocal(a),
            d = self:GetLocal(d),
        })
        self:Next()
        self:Write("end;")
    end

    function OPS:ISF(a, b, c, d)
        -- Copy D to A and jump, if D is false
        self:WriteP("if(not {d})then ", {
            a = self:GetLocal(a),
            d = self:GetLocal(d),
        })
        self:Next()
        self:Write("end;")
    end
    -- End Unary Test and Copy Ops

    -- Unary Ops
    function OPS:MOV(a, b, c, d)
        local var = self:GetLocal(d)
        self:SetLocal(a, var)
    end

    function OPS:NOT(a, b, c, d)
        local var = self:GetLocal(d)
        self:SetLocal(a, "not " .. var)
    end

    function OPS:UNM(a, b, c, d)
        local var = self:GetLocal(d)
        self:SetLocal(a, "-" .. var)
    end

    function OPS:LEN(a, b, c, d)
        local var = self:GetLocal(d)
        self:SetLocal(a, "#(" .. var .. ")")
    end
    -- End Unary Ops

    -- Binary Ops
    function OPS:ADDVN(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "+" .. self:GetNConst(c))
    end

    function OPS:SUBVN(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "-" .. self:GetNConst(c))
    end

    function OPS:MULVN(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "*" .. self:GetNConst(c))
    end

    function OPS:DIVVN(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "/" .. self:GetNConst(c))
    end

    function OPS:MODVN(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "%" .. self:GetNConst(c))
    end

    function OPS:ADDNV(a, b, c, d)
        self:SetLocal(a, self:GetNConst(c) .. "+" .. self:GetLocal(b))
    end

    function OPS:SUBNV(a, b, c, d)
        self:SetLocal(a, self:GetNConst(c) .. "-" .. self:GetLocal(b))
    end

    function OPS:MULNV(a, b, c, d)
        self:SetLocal(a, self:GetNConst(c) .. "*" .. self:GetLocal(b))
    end

    function OPS:DIVNV(a, b, c, d)
        self:SetLocal(a, self:GetNConst(c) .. "/" .. self:GetLocal(b))
    end

    function OPS:MODNV(a, b, c, d)
        self:SetLocal(a, self:GetNConst(c) .. "%" .. self:GetLocal(b))
    end

    function OPS:ADDVV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "+" .. self:GetLocal(c))
    end

    function OPS:SUBVV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "-" .. self:GetLocal(c))
    end

    function OPS:MULVV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "*" .. self:GetLocal(c))
    end

    function OPS:DIVVV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "/" .. self:GetLocal(c))
    end

    function OPS:MODVV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "%" .. self:GetLocal(c))
    end

    function OPS:POW(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "^" .. self:GetLocal(c))
    end

    function OPS:CAT(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b))
        for i = b + 1, c do
            self:SetLocal(a, self:GetLocal(a) .. ".." .. self:GetLocal(i))
        end
    end
    -- End Binary Ops

    -- Constant Ops
    function OPS:KSTR(a, b, c, d)
        local const = self:GetGCConst(d)
        const = self:ToLuaVal(const)
        self:SetLocal(a, const)
    end

    function OPS:KSHORT(a, b, c, d)
        if d >= 0x8000 then
            d = d - 0x10000  -- Convert to negative value if the sign bit (bit 15) is set
        end
        d = self:Num(d)
        self:SetLocal(a, d)
    end

    function OPS:KNUM(a, b, c, d)
        local const = self:GetNConst(d)
        self:SetLocal(a, const)
    end

    function OPS:KPRI(a, b, c, d)
        d = self:Pri(d)
        self:SetLocal(a, d)
    end

    function OPS:KNIL(a, b, c, d)
        for i = a, c do
            self:SetLocal(i, "nil")
        end
    end
    -- End Constant Ops

    -- Upvalue and Function Ops
    function OPS:UGET(a, b, c, d)
        local uv_local = self:GetUV(d)
        self:SetLocal(a, uv_local)
    end

    function OPS:USETV(a, b, c, d)
        local local_var = self:GetLocal(d)
        self:SetUV(a, local_var)
    end

    function OPS:USETS(a, b, c, d)
        local const = self:GetGCConst(d)
        const = self:ToLuaVal(const)
        self:SetUV(a, const)
    end

    function OPS:USETN(a, b, c, d)
        local const = self:GetNConst(d)
        self:SetUV(a, const)
    end

    function OPS:USETP(a, b, c, d)
        d = self:Pri(d)
        self:SetUV(a, d)
    end

    function OPS:UCLO(a, b, c, d)
        -- Close upvalues for slots >= a: give each captured slot a FRESH box
        -- carrying its current value. Closures made in earlier iterations keep
        -- their old box (old value); the next iteration writes into the new one.
        if self.boxed then
            for slot in pairs(self.boxed) do
                if slot >= a then
                    local box = self:Name("locals") .. "[" .. slot .. "]"
                    self:Writef("%s={%s[1]};", box, box)
                end
            end
        end
        OPS.JMP(self, 0, 0, 0, d)
    end

    function OPS:FNEW(a, b, c, d)
        local proto = self:GetGCConst(d)
        local obf = Obfuscator(proto, self)
        -- Collect boxed slots this child captures; give each a param name.
        obf.captured_boxes = {}
        local params_list, args_list = {}, {}
        for uv = 0, obf.upvalues - 1 do
            local uvinfo = get_uv_info(proto, uv)
            if uvinfo.is_local and self:IsBoxed(uvinfo.slot_id) then
                local pname = self:Name("cap_" .. self.pc .. "_" .. uvinfo.slot_id)
                obf.captured_boxes[uvinfo.slot_id] = pname
                table.insert(params_list, pname)
                table.insert(args_list, ("%s[%d]"):format(self:Name("locals"), uvinfo.slot_id))
            end
        end
        if DEBUGGING then print("NEW-SCOPE " .. obf.id) end
        obf:Start()
    
        local wrap = #params_list > 0
        if wrap then
            self:Writef("%s=(function(%s)return function(",
                self:GetLocal(a), table.concat(params_list, ","))
        else
            self:Writef("%s=function(", self:GetLocal(a))
        end
    
        local max = obf.params - 1
        for i = 0, max do
            self:Writef("%s", obf:Name("params" .. i))
            if i < max then self:Write(",") end
        end
        if obf.isvararg then
            self:Write(max > -1 and ",..." or "...")
        end
        self:Write(")")
    
        self:Write(obf:Dump())
        self:Write("end;")
    
        if wrap then
            self:Writef("end)(%s);", table.concat(args_list, ","))
        end
    
        if DEBUGGING then print("END-SCOPE " .. obf.id) end
    end
    -- End Upvalue and Function Ops

    -- Table Ops
    function OPS:TNEW(a, b, c, d)
        self:SetLocal(a, "{}")
    end

    function OPS:TDUP(a, b, c, d)
        local dup_tbl = self:GetGCConst(d)

        self:SetLocal(a, "{}")
        for k, v in pairs(dup_tbl) do
            self:WriteP("{a}[{k}]={v};", {
                a = self:GetLocal(a),
                k = self:ToLuaVal(k),
                v = self:ToLuaVal(v),
            })
        end
    end

    function OPS:GGET(a, b, c, d)
        local const = self:GetGCConst(d)
        self:SetLocal(a, ("%s()['%s']"):format(self:GetFuncName("getfenv"), const))
    end

    function OPS:GSET(a, b, c, d)
        local const = self:GetGCConst(d)
        self:WriteP("{getfenv}()['{const}']={a};", {
            a = self:GetLocal(a),
            const = const,
            getfenv = self:GetFuncName("getfenv"),
        })
    end

    function OPS:TGETV(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "[" .. self:GetLocal(c) .. "]")
    end

    function OPS:TGETS(a, b, c, d)
        local const = self:GetGCConst(c)
        const = self:ToLuaVal(const)
        self:SetLocal(a, self:GetLocal(b) .. "[" .. const .. "]")
    end

    function OPS:TGETB(a, b, c, d)
        self:SetLocal(a, self:GetLocal(b) .. "[" .. c .. "]")
    end

    function OPS:TSETV(a, b, c, d)
        self:WriteP("{b}[{c}]={a};", {
            a = self:GetLocal(a),
            b = self:GetLocal(b),
            c = self:GetLocal(c),
        })
    end

    function OPS:TSETS(a, b, c, d)
        local const = self:GetGCConst(c)
        const = self:ToLuaVal(const)
        self:WriteP("{b}[{const}]={a};", {
            a = self:GetLocal(a),
            b = self:GetLocal(b),
            const = const,
        })
    end

    function OPS:TSETB(a, b, c, d)
        self:WriteP("{b}[{c}]={a};", {
            a = self:GetLocal(a),
            b = self:GetLocal(b),
            c = c,
        })
    end

    function OPS:TSETM(a, b, c, d)
        local start = self:GetNConst(d) - 2^52 -- the lowest 32 bits from the mantissa are used as a starting table index
        local i = self:Name("TSETM_i")
        self:WriteP("for {i}=0,{multires}-1 do ", {
            i = i,
            multires = self:Name("multires"),
        })
        self:WriteP("{tbl}[{start}+{i}]={returns}[{i}+1];", {
            tbl = self:GetLocal(a - 1),
            start = start,
            i = i,
            returns = self:Name("returns"),
        })
        self:Write("end;")
    end
    -- End Table Ops

    -- Calls and Vararg Handling
    function OPS:CALL(a, b, c, d)
        local nargs = c - 1
        local nresults = b - 1

        local MULTIRES = self.current_ins.op_name == "CALLM"
        if not MULTIRES then
            nargs = nargs - 1 -- CALL
        end

        local args = {}
        for i = 0, nargs do
            table.insert(args, self:GetLocal((a + 2) + i))
        end

        if MULTIRES then
            table.insert(args, ("%s(%s,1,%s)"):format(self:GetFuncName("unpack"), self:Name("returns"), self:Name("multires")))
        end

        self:WriteP("{returns},{multires}={table_pack}({func}({args}))", {
            returns = self:Name("returns"),
            multires = self:Name("multires"),
            table_pack = self:TablePackName(),
            func = self:GetLocal(a),
            args = table.concat(args, ","),
        })

        for i = 0, nresults - 1 do
            local idx = a + i
            self:SetLocal(idx, ("%s[%s]"):format(self:Name("returns"), i + 1))
        end
    end
    OPS.CALLM = OPS.CALL

    function OPS:CALLT(a, b, c, d)
        local nargs = c - 1

        local MULTIRES = self.current_ins.op_name == "CALLMT"
        if not MULTIRES then
            nargs = nargs - 1 -- CALLT
        end

        local args = {}
        for i = 0, nargs do
            table.insert(args, self:GetLocal((a + 2) + i))
        end

        if MULTIRES then
            table.insert(args, ("%s(%s,1,%s)"):format(self:GetFuncName("unpack"), self:Name("returns"), self:Name("multires")))
        end

        self:WriteP("{returns},{multires}={table_pack}({func}({args}))", {
            returns = self:Name("returns"),
            multires = self:Name("multires"),
            table_pack = self:TablePackName(),
            func = self:GetLocal(a),
            args = table.concat(args, ","),
        })

        self:Writef("do return %s(%s,1,%s);end;", self:GetFuncName("unpack"), self:Name("returns"), self:Name("multires"))
    end
    OPS.CALLMT = OPS.CALLT

    function OPS:ITERC(a, b, c, d)
        self:SetLocal(a, self:GetLocal(a - 3))
        self:SetLocal(a + 1, self:GetLocal(a - 2))
        self:SetLocal(a + 2, self:GetLocal(a - 1))

        local start, ending = a, a + b - 2
        for i = start, ending do
            self:Writef("%s%s", self:GetLocal(i), i < ending and "," or "=")
        end

        self:Writef("%s(%s,%s);", self:GetLocal(a), self:GetLocal(a + 1), self:GetLocal(a + 2))
    end
    OPS.ITERN = OPS.ITERC

    function OPS:VARG(a, b, c, d)
        if b == 0 then -- MULTRES
            self:WriteP("{returns},{multires}={table_pack}(...);", {
                returns = self:Name("returns"),
                multires = self:Name("multires"),
                table_pack = self:TablePackName(),
            })
        else
            for i = a, a + b - 1 do
                self:SetLocal(i, ("({...})[%s]"):format(i - a + 1))
            end
        end
    end

    function OPS:ISNEXT(a, b, c, d)
        OPS.JMP(self, a, b, c, d)
    end
    -- End Calls and Vararg Handling

    -- Return Ops
    function OPS:RETM(a, b, c, d)
        local rets = ""
        for i = a, a + d - 1 do
            rets = rets .. self:GetLocal(i) .. ","
        end
        self:Writef("do return %s", rets)
        self:Writef("%s(%s,1,%s);", self:GetFuncName("unpack"), self:Name("returns"), self:Name("multires"))
        self:Write("end;")
    end

    function OPS:RET(a, b, c, d)
        local rets = ""
        for i = a, a + d - 2 do
            rets = rets .. self:GetLocal(i) .. ","
        end
        rets = rets:sub(1, -2) -- remove last comma
        self:Writef("do return %s", rets)
        self:Write("end;")
    end

    function OPS:RET0(a, b, c, d)
        self:Write("do return;end;")
    end

    function OPS:RET1(a, b, c, d)
        self:WriteP("do return {a};end;", {
            a = self:GetLocal(a),
        })
    end

    function OPS:FORI(a, b, c, d)
        local start = self:GetLocal(a)
        local ending = self:GetLocal(a + 1)
        local step = self:GetLocal(a + 2)

        local i_iter = self:GetLocal(a + 3)
        self:SetLocal(a + 3, start)

        self:Writef("if(%s>0)then ", step)
            self:WriteP("if({i_iter}>{ending})then ", {
                i_iter = i_iter,
                ending = ending,
            })
                OPS.JMP(self, 0, 0, 0, d)
            self:Write("end;")
        self:Write("else ")
            self:WriteP("if({step}<0)and({i_iter}<{ending})then ", {
                step = step,
                i_iter = i_iter,
                ending = ending,
            })
                OPS.JMP(self, 0, 0, 0, d)
            self:Write("end;")
        self:Write("end;")
    end

    function OPS:FORL(a, b, c, d)
        local ending = self:GetLocal(a + 1)
        local step = self:GetLocal(a + 2)

        local i_iter = self:GetLocal(a + 3)
        self:SetLocal(a + 3, i_iter .. "+" .. step)

        self:WriteP("if({step}>0)then ", {
            step = step,
        })
            self:WriteP("if({i_iter}<=({ending}))then ", {
                i_iter = i_iter,
                ending = ending,
            })
                OPS.JMP(self, 0, 0, 0, d)
            self:Write("end;")
        self:Write("else ")
            self:WriteP("if({step}<0)and({i_iter}>=({ending}))then ", {
                step = step,
                i_iter = i_iter,
                ending = ending,
            })
                OPS.JMP(self, 0, 0, 0, d)
            self:Write("end;")
        self:Write("end;")
    end

    function OPS:LOOP()
        -- no-op
    end
    -- End Return Ops

    -- Loops and branches Ops
    function OPS:ITERL(a, b, c, d)
        self:Writef("if(%s~=nil)then ", self:GetLocal(a))
        self:SetLocal(a - 1, self:GetLocal(a))
        OPS.JMP(self, 0, 0, 0, d)
        self:Write("end;")
    end
    -- End Loops and branches Ops

    function OPS:JMP(a, b, c, d)
        local jmp_pos = self:GetJMPPos(self.pc, d)
        self:Writef("goto _%d_%d;", self.id, jmp_pos)
    end
end

do
    local hex_buffer = buffer.new()
    local function string_to_hex(str)
        hex_buffer:reset()
        for i = 1, #str do
            local byte = str:byte(i)
            hex_buffer:putf("'\\x%02X'", byte)
        end
        return (hex_buffer:tostring())
    end

    local dehex_code

    local PREPARING
    function MINGE_STR(str)
        if str == "" then
            return "''"
        end
        if PREPARING then
            return string_to_hex(str)
        end
        if not OBFUSCATING_MODE then
            return ("%q"):format(str)
        end

        local hexTable = "{"
        for i = 1, #str do
            local byte = string.byte(str, i)
            hexTable = hexTable .. ("0x%02x,"):format(byte)
        end
        hexTable = hexTable .. "}"

        local lovely_string = ("(function(...)%send)()(%s)"):format(dehex_code, hexTable)
        return lovely_string
    end

    dehex_code = [=[
        return function(...)
            local ascii_map = {[0]='\x00',[1]='\x01',[2]='\x02',[3]='\x03',[4]='\x04',[5]='\x05',[6]='\x06',[7]='\x07',[8]='\x08',[9]='\x09',[10]='\x0A',[11]='\x0B',[12]='\x0C',[13]='\x0D',[14]='\x0E',[15]='\x0F',[16]='\x10',[17]='\x11',[18]='\x12',[19]='\x13',[20]='\x14',[21]='\x15',[22]='\x16',[23]='\x17',[24]='\x18',[25]='\x19',[26]='\x1A',[27]='\x1B',[28]='\x1C',[29]='\x1D',[30]='\x1E',[31]='\x1F',[32]='\x20',[33]='\x21',[34]='\x22',[35]='\x23',[36]='\x24',[37]='\x25',[38]='\x26',[39]='\x27',[40]='\x28',[41]='\x29',[42]='\x2A',[43]='\x2B',[44]='\x2C',[45]='\x2D',[46]='\x2E',[47]='\x2F',[48]='\x30',[49]='\x31',[50]='\x32',[51]='\x33',[52]='\x34',[53]='\x35',[54]='\x36',[55]='\x37',[56]='\x38',[57]='\x39',[58]='\x3A',[59]='\x3B',[60]='\x3C',[61]='\x3D',[62]='\x3E',[63]='\x3F',[64]='\x40',[65]='\x41',[66]='\x42',[67]='\x43',[68]='\x44',[69]='\x45',[70]='\x46',[71]='\x47',[72]='\x48',[73]='\x49',[74]='\x4A',[75]='\x4B',[76]='\x4C',[77]='\x4D',[78]='\x4E',[79]='\x4F',[80]='\x50',[81]='\x51',[82]='\x52',[83]='\x53',[84]='\x54',[85]='\x55',[86]='\x56',[87]='\x57',[88]='\x58',[89]='\x59',[90]='\x5A',[91]='\x5B',[92]='\x5C',[93]='\x5D',[94]='\x5E',[95]='\x5F',[96]='\x60',[97]='\x61',[98]='\x62',[99]='\x63',[100]='\x64',[101]='\x65',[102]='\x66',[103]='\x67',[104]='\x68',[105]='\x69',[106]='\x6A',[107]='\x6B',[108]='\x6C',[109]='\x6D',[110]='\x6E',[111]='\x6F',[112]='\x70',[113]='\x71',[114]='\x72',[115]='\x73',[116]='\x74',[117]='\x75',[118]='\x76',[119]='\x77',[120]='\x78',[121]='\x79',[122]='\x7A',[123]='\x7B',[124]='\x7C',[125]='\x7D',[126]='\x7E',[127]='\x7F',[128]='\x80',[129]='\x81',[130]='\x82',[131]='\x83',[132]='\x84',[133]='\x85',[134]='\x86',[135]='\x87',[136]='\x88',[137]='\x89',[138]='\x8A',[139]='\x8B',[140]='\x8C',[141]='\x8D',[142]='\x8E',[143]='\x8F',[144]='\x90',[145]='\x91',[146]='\x92',[147]='\x93',[148]='\x94',[149]='\x95',[150]='\x96',[151]='\x97',[152]='\x98',[153]='\x99',[154]='\x9A',[155]='\x9B',[156]='\x9C',[157]='\x9D',[158]='\x9E',[159]='\x9F',[160]='\xA0',[161]='\xA1',[162]='\xA2',[163]='\xA3',[164]='\xA4',[165]='\xA5',[166]='\xA6',[167]='\xA7',[168]='\xA8',[169]='\xA9',[170]='\xAA',[171]='\xAB',[172]='\xAC',[173]='\xAD',[174]='\xAE',[175]='\xAF',[176]='\xB0',[177]='\xB1',[178]='\xB2',[179]='\xB3',[180]='\xB4',[181]='\xB5',[182]='\xB6',[183]='\xB7',[184]='\xB8',[185]='\xB9',[186]='\xBA',[187]='\xBB',[188]='\xBC',[189]='\xBD',[190]='\xBE',[191]='\xBF',[192]='\xC0',[193]='\xC1',[194]='\xC2',[195]='\xC3',[196]='\xC4',[197]='\xC5',[198]='\xC6',[199]='\xC7',[200]='\xC8',[201]='\xC9',[202]='\xCA',[203]='\xCB',[204]='\xCC',[205]='\xCD',[206]='\xCE',[207]='\xCF',[208]='\xD0',[209]='\xD1',[210]='\xD2',[211]='\xD3',[212]='\xD4',[213]='\xD5',[214]='\xD6',[215]='\xD7',[216]='\xD8',[217]='\xD9',[218]='\xDA',[219]='\xDB',[220]='\xDC',[221]='\xDD',[222]='\xDE',[223]='\xDF',[224]='\xE0',[225]='\xE1',[226]='\xE2',[227]='\xE3',[228]='\xE4',[229]='\xE5',[230]='\xE6',[231]='\xE7',[232]='\xE8',[233]='\xE9',[234]='\xEA',[235]='\xEB',[236]='\xEC',[237]='\xED',[238]='\xEE',[239]='\xEF',[240]='\xF0',[241]='\xF1',[242]='\xF2',[243]='\xF3',[244]='\xF4',[245]='\xF5',[246]='\xF6',[247]='\xF7',[248]='\xF8',[249]='\xF9',[250]='\xFA',[251]='\xFB',[252]='\xFC',[253]='\xFD',[254]='\xFE',[255]='\xFF'}
            local str = ""
            for i = 1, #... do
                str = str .. ascii_map[(...)[i]]
            end
            return str
        end
    ]=]

    PREPARING = true
    dehex_code = Obfuscator(loadstring(dehex_code))
    dehex_code:Start()
    dehex_code = dehex_code:Dump()
    PREPARING = false
end

-- local OLD_PRINT, OLD_IO_WRITE = print, io.write
-- -- this function disables outputting to console and saves the outputs in a variable
-- function capture_prints()
--     local output = ""
--     function print(...)
--         for k, v in ipairs({...}) do
--             output = output .. tostring(v)
--         end
--     end
--
--     function io.write(...)
--         for k, v in ipairs({...}) do
--             output = output .. tostring(v)
--         end
--     end
--
--     return function()
--         print = OLD_PRINT
--         io.write = OLD_IO_WRITE
--         return output
--     end
-- end
--
-- function capture_outputs(f, ...)
--     local capture = capture_prints()
--     local status, err = pcall(f, ...)
--     local output = capture()
--     output = output .. (status and (err or "") or "Error: " .. err)
--     return output
-- end
--
-- local to_test_func = loadfile("obfuscator/test.lua")
--
-- local obf = Obfuscator(to_test_func)
-- obf:Start()
--
-- local args = {1, 2, 3, 4}
-- if true then
--     local original_o = capture_outputs(to_test_func, unpack(args))
--     rawset(_G, "stat", nil)
--     local obf_o = capture_outputs(loadstring(obf:Dump()), unpack(args))
--     if original_o ~= obf_o then
--         print("Outputs are different")
--         print("Original: " .. original_o)
--         print("Obfuscated: " .. obf_o)
--     else
--         print("Outputs are the same")
--     end
-- end

local function write_file(fn, data)
    local f, err = io.open(fn, "w")
    if not f then
        return false, err
    end
    f:write(data)
    f:close()
    return true
end

-- write_file("obfuscator/obfuscated.lua", obf:Dump())

local OBFUSCATE_TIMES = 1
local OUTPUT_FILE

local function obfuscate_code(code, n)
    local proto, err = loadstring(code)
    if not proto then
        return false, err
    end
    local obf = Obfuscator(loadstring(code))
    obf:Start()
    local output = obf:Dump()
    if n > 1 then
        return obfuscate_code(output, n - 1)
    end
    return true, output
end

print("Enter code to obfuscate:")
print("Enter -n <number> to set the extra obfuscation level (e.g. -n 2)")
print("Enter -o <file_name> to write the obfuscated code to a file (e.g. -o obfuscated.lua) (make sure directory exists!)")

while true do
    local line = io.read()
    if not line then
        break
    end

    if line == "quit" or line == "exit" or line == "q" then
        break
    end

    if line:match("^%-n%s+%d+$") then
        local n = tonumber(line:match("%d+"))
        if n then
            OBFUSCATE_TIMES = n
        end
        print("Extra obfuscation level set to " .. n)
        goto _continue_
    end

    if line:match("^%-o%s+.+$") then
        local filename = line:match("%-o%s+(.+)")
        print("Writing obfuscated code to `" .. filename .. "`")
        OUTPUT_FILE = filename
        goto _continue_
    end

    local status, output = obfuscate_code(line, OBFUSCATE_TIMES)
    if status then
        if OUTPUT_FILE then
            local status, err = write_file(OUTPUT_FILE, output)
            if not status then
                print("Error writing file: " .. err)
            else
                print("Obfuscated code written to " .. OUTPUT_FILE)
            end
        else
            print(output)
        end
    else
        print("Error: " .. output)
    end

    collectgarbage("collect")

    ::_continue_::
end
