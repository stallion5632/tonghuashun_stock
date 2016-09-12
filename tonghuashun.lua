local cjson = require("cjson.safe")
local http = require("socket.http")

http.TIMEOUT = 3   --TIMEOUT

local exchange 

local function split(str, delimiter)
    if str == nil or str=='' or delimiter == nil then
        return nil
    end

    local result = {}
    for match in (str..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end




local trade_times = {
    NASDAQ = {"09:30-16:00"},
    INDEXDJX = {"09:30-16:00"},
    INDEXNASDAQ = {"09:30-16:00"},
    INDEXSP = {"09:30-16:00"},
    NYSE = {"09:30-16:00"},
    SH = {"09:30-11:30", "13:00-15:00"},
    SZ = {"09:30-11:30", "13:00-15:00"},
    HK = {"09:30-12:00", "13:00-16:00"},
}

local trade_closetime =
{
    SH = {'11:30', '13:00', '15:00'},
    SZ = {'11:30', '13:00',  '15:00'},
    HK = {'12:00', '13:00', '16:00'},
    other = '16:00'
}

local function builderr(errId, err)
    return {errId = not errId and 500 or errId, ['error'] = err}
end


local function getdate_tonghuashun(date, time)
    if not date or not  time then 
    	return
    end
    assert(#date == 8)
    local y,m,d,h,min
    y = string.sub(date, 1,4)
    m = string.sub(date, 5,6)
    d = string.sub(date, 7,8)
    h = string.sub(time, 1,2)
    min = string.sub(time, 3,4)
    return y..'-'..m ..'-' .. d .. 'T'..h ..':'..min .. ':' .. '00' .. '+08:00'
end

--suspend not data
local function process_tonghuashun_query( symbol,exchange )
	local today = os.date("%Y-%m-%d", os.time())
    local errId, err, response
    assert(exchange)
    assert(symbol)
    local url_basic,url_min

    local s = string.sub(symbol, 1, 2) 
	if tonumber(s) then --前两位是数字，否则
		symbolcode = symbol
	elseif  s == 'HK' or s == "SH" or s == 'SZ' then--前两位是SH SZ HK
		symbolcode = string.sub(symbol, 3)
	end


	local lastClose, open, high, low, currrent, volume, amount, percentage, turnoverRate,headlen, name, tag, data, date, data_t, list, chart, updatedate
    local 	symbolcode = 'QIHU'
	if exchange == 'SH' or exchange == 'SZ' then
		url_basic =  'http://qd.10jqka.com.cn/quote.php?cate=real&type=stock&return=json&callback=showStockData&code=' .. symbolcode
		url_min =  'http://d.10jqka.com.cn/v2/time/hs_'..symbolcode .. '/last.js' 
		tag = 'hs_'..symbolcode
	elseif exchange == 'HK' then
		url_basic = 'http://stockpage.10jqka.com.cn/HK'..symbolcode .. '/quote/quotation/'
		url_min =  'http://d.10jqka.com.cn/v2/time/hk_HK'..symbolcode .. '/last.js' 
		tag = 'hk_HK'..symbolcode
	elseif exchange == 'US' then
		url_basic = 'http://stockpage.10jqka.com.cn/'..symbolcode..'/quote/quotation/'
		url_min = 'http://d.10jqka.com.cn/v2/time/usa_' .. symbolcode .. '/last.js'
		tag = 'usa_' .. symbolcode
	end

	local body, code = http.request(url_basic)
	if code ~= 200 then
		return false, builderr(500, 'request failed')
	end

	if exchange == 'SH' and exchange == 'SZ' then
		headlen = #'showStockData('
		body = string.sub(body, headlen+1, -2 )
	end

	-- return false, nil
	local t = cjson.decode(body)
	if t then
		if  t.info and t.info[symbolcode] and t.info[symbolcode].name then 
			name = t.info[symbolcode].name 
		end
		if  t.data  then 
			if  t.data[symbolcode] then
				t = t.data[symbolcode] 
			elseif  t.data[exchange..symbolcode] then
				t = t.data[exchange..symbolcode] 
			end
		end

		assert(t)

		if t['6'] then lastClose = t['6'] end

		if t['7'] then	open = t['7']	end

		if t['8'] then	high = t['8']	end

		if t['9'] then	low = t['9'] end

		if t['10'] then	currrent = t['10']	end

		if t['13'] and tonumber(t['13']) then 
			volume = t['13'] 
			volume = string.format('%.7fE7', tonumber(volume)/10000000)
		end
		if t['19']  and tonumber(t['19'])then 
			amount = t['19'] 
			amount = string.format('%.8fE8', tonumber(amount)/100000000)
		end
		if t['2034120'] then peTTM = t['2034120'] end
		if t['526792'] then 
			percentage = t['526792'] 
			percentage = string.format('%.2f', percentage)
		end

		if t['1968584'] and tonumber(turnoverRate) then 
			turnoverRate = t['1968584'] 
			turnoverRate = string.format('%.2f', tonumber(turnoverRate))
		end
	end

	local body, code = http.request(url_min)
	if code ~= 200 then
		return false, builderr(500, 'request failed')
	end

	if exchange == 'SH' and exchange == 'SZ' then
		headlen = #('quotebridge_v2_time_hs_'.. symbolcode ..'_last(')
		body = string.sub(body, headlen+1, -2 )
	elseif exchange == 'HK' then
		headlen = #('quotebridge_v2_time_hk_HK'..symbolcode..'_last(')
		body = string.sub(body, headlen+1, -2 )
	elseif exchange == 'US' then
		headlen = #('quotebridge_v2_time_usa_'..symbolcode..'_last(')
		body = string.sub(body, headlen+1, -2 )
	end

	t = cjson.decode(body)
	data = t[tag].data
	updatedate = t[tag].date
	data_t = split(data, ';')
	list = {}
	for _,v in ipairs(data_t) do
		--0930,5.59,1715763,5.585,307200
		--价5.59 均5.58 涨跌0.04 涨幅0.72 量30.72万手 额171.58
		t = split(v, ',')
		time = t[1]
		date = getdate_tonghuashun(updatedate, time)
		table.insert(list, {date = date, price = t[2], volume = t[5] })
	end
	chart = {period = "1minute", list = list}
	updatedate = list[#list].date

	--showStockData({"info":{"600027":{"name":"\u534e\u7535\u56fd\u9645"}},"data":{"600027":{"6":"5.55"(昨收),"7":"5.58"(今开),"8":"5.66"(最高),"9":"5.56"(最低),"10":"5.66"(当前),"11":"","12":"1","13":"32932310.00"(成交量),"14":"19092273.00","15":"13794437.00","17":"75300.00","19":"185032700.00"(成交额),"69":"6.11","70":"5.00","526792":"1.802"(振幅),"3475914":"33620718000.000"(336.21),"264648":"0.110","199112":"1.982","1968584":"0.554"(换手),"2034120":"7.256"(市盈率(动)),"1378761":"5.619","1771976":"1.400","461256":"-22.998","395720":"-1321818.000"}}})



    local result = {
            symbol = symbol,  --证券唯一标识, 全球唯一
            low = low,     --最低
            high = high,     --最高
            amount = amount,   --成交额
            volume = volume,   --成交量
            turnoverRate = turnoverRate,    --换手率
            currrent = currrent,  --当前价
            lastClose = lastClose,  --昨收
            change = tonumber(currrent) - tonumber(lastClose),  --涨/跌
            percentage = percentage,    --涨/跌幅
            date = updatedate,        --行情更新时间
            name =  name,       --股票名称，不同交易所间可能重复
            exchange = exchange,    --交易所大写缩写 沪: SH, 深: SZ, 港: HK, 纽交所: NYSE, 纳斯达克: NASDAQ
            code = symbolcode,      --股票代码
            peLYR = '',     --静态市盈率
            peTTM = peTTM,        --动态市盈率
            open = open,    --今开
            chart = chart,
            tradeTime = trade_times[exchange] or {"09:30-16:00"},
            state = ''
    }
    
    print(cjson.encode({result = result}))
	return true, result
end
process_tonghuashun_query('QIHU', 'US')



--[[
result 格式： 
{
    "result": {
        "chart": {
            "list": [
                {
                    "date": "2016-02-15T15:14:54+08:00",
                    "price": 26.06,
                    "volume": 798848
                },
                //....
                {
                    "date": "2016-02-15T15:14:54+08:00",
                    "price": 28.41,
                    "volume": 509583
                }
            ],
            "period": "1minute"
        },
        "symbol": "SZ002230",  // 证券唯一标识, 全球唯一
        "low": "26.0",         // 最低
        "currrent": "29.46",   // 当前价,
        "peLYR": "99.8359",     // 静态市盈率
        "peTTM": "93.534",      // 动态市盈率
        "turnoverRate": "4.93", //换手率
        "high": "29.46",        // 最高
        "lastClose": "26.78",    // 昨收
        "percentage": "10.01",  // 涨/跌幅
        "change": "2.68",       // 涨/跌
        "code": "002230",       //股票代码
        "amount": "1.39852102033E9",  // 成交额
        "open": "26.0",             // 今开
        "date": "2016-02-15T15:14:54+08:00",  // 行情更新时间
        "volume": "4.9228172E7",            // 成交量
        "name": "科大讯飞",         //股票名称，不同交易所间可能重复, 比如阿里巴巴在港交所和纽交所都有
        "exchange": "SZ"            // 交易所大写缩写 沪: SH, 深: SZ, 港: HK, 纽交所: NYSE, 纳斯达克: NASDAQ
    }
}
]]--
