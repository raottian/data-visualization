#=
senior_stay:
- Julia version: 
- Author: letian
- Date: 2019-03-23
=#

using MySQL
using DataFrames
using Missings

conn = MySQL.connect("139.224.15.45", "icare", "ginkodrop", db = "vsi_dw_etl")
sql="""select oca.requestId,oca.subcompanyid,senior.id as senior_id,
       (case 操作节点
            when "发起申请" then "A"
            WHEN "SM" then "B"
            when "用户体验" then "C"
            WHEN "门店确认入住" THEN "D"
            WHEN "归档" THEN "E"  ELSE "F" END) as nodename,
       month(接收到日期) as start_month,day(接收到日期) as start_day,month(操作日期) as end_month,day(操作日期) as end_day,
(case 流程是否归档 when "已归档" then True else False end) as archive_status from oa_checkin_assessment oca
left join oa_allflow_state oas on oca.requestId=oas.requestid
left join operating_reports.oa_domain_map_test oamt on oamt.subcompanyid=rzjg
left join senior on senior.domain_id=oamt.domain_id and senior.name=lrxm
"""

df=MySQL.Query(conn, sql) |> DataFrame

# senior_id drop missing
df=dropmissing(df,:senior_id)
df=dropmissing(df,:start_month)

# end fill missing
now_month=3
now_day=24
df[:end_month]=collect(Missings.replace(df[:end_month], now_month))
df[:end_day]=collect(Missings.replace(df[:end_day], now_day))

# duration=second(start-end)
@linq df |>select(:requestId,:subcompanyid,:senior_id,:nodename,:archive_status,
    duration=(:end_month-:start_month)*30+(:end_day-:start_day))

# archive_status=>string -> bool
@linq df |>select(:requestId,:subcompanyid,:senior_id,:nodename,archive_status=(:archive_status.=="已归档"))

# sort
sort!(df, (:requestId,:end_month, :end_day),
                    rev = (true,true, true));

# current_node=node in maximum date
df[:index]=1:size(df,1)
current_df=@linq df |>by(:requestId,max_index=maximum(:index))
node_df=df[[:requestId,:index,:nodename]]
current_df=join(current_df,node_df,on=[:requestId,:index],kind=:left)
current_df=rename(current_df, :nodename => :current_nodename)
df=join(df,current_df,on=[:requestId,:index],kind=:left)
df=df[[:requestId,:subcompanyid,:senior_id,:nodename,:archive_status,:current_nodename]]

# to_sql
my_stmt = MySQL.Stmt(conn, """INSERT INTO senior_stay_table
    ('requestId','subcompanyid','senior_id','nodename','archive_status','current_nodename')
    VALUES (?,?,?,?,?,?);""")

for i = 1:size(df,1)
  MySQL.execute!(my_stmt, [i, "df_$i"])
end

MySQL.disconnect(conn)