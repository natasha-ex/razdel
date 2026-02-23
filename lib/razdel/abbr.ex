defmodule Razdel.Abbr do
  @moduledoc "Russian abbreviation database for sentence boundary detection."

  @tail_abbrs MapSet.new(~w[
    дес тыс млн млрд дол долл коп руб р проц
    га барр куб кв км см
    час мин сек в вв г гг с стр
    co corp inc изд ed др al
  ])

  @head_abbrs MapSet.new(~w[
    букв ст трад
    лат венг исп кат укр нем англ фр итал греч евр араб яп слав кит рус русск латв словацк хорв
    mr mrs ms dr vs
    св арх зав зам проф акад кн корр ред гр ср чл им тов
    нач пол chap
    п пп ст ч чч гл стр абз пт no
    просп пр ул ш г гор д стр к корп пер корп обл эт пом ауд оф ком комн каб
    домовлад лит т рп пос с х пл bd о оз р а
    обр ум ок откр пс ps upd см напр доп
    юр физ тел сб внутр дифф гос отм
  ])

  @other_abbrs MapSet.new(~w[сокр рис искл прим яз устар шутл])

  @all_abbrs MapSet.union(@tail_abbrs, MapSet.union(@head_abbrs, @other_abbrs))

  @tail_pair_abbrs MapSet.new([
                     {"т", "п"},
                     {"т", "д"},
                     {"у", "е"},
                     {"н", "э"},
                     {"p", "m"},
                     {"a", "m"},
                     {"с", "г"},
                     {"р", "х"},
                     {"с", "ш"},
                     {"з", "д"},
                     {"л", "с"},
                     {"ч", "т"}
                   ])

  @head_pair_abbrs MapSet.new([
                     {"т", "е"},
                     {"т", "к"},
                     {"т", "н"},
                     {"и", "о"},
                     {"к", "н"},
                     {"к", "п"},
                     {"п", "н"},
                     {"к", "т"},
                     {"л", "д"}
                   ])

  @other_pair_abbrs MapSet.new([
                      {"ед", "ч"},
                      {"мн", "ч"},
                      {"повел", "накл"},
                      {"жен", "р"},
                      {"муж", "р"}
                    ])

  @all_pair_abbrs MapSet.union(
                    @tail_pair_abbrs,
                    MapSet.union(@head_pair_abbrs, @other_pair_abbrs)
                  )

  @initials MapSet.new(~w[дж ed вс])

  def head_abbr?(word), do: MapSet.member?(@head_abbrs, word)
  def abbr?(word), do: MapSet.member?(@all_abbrs, word)
  def head_pair_abbr?(pair), do: MapSet.member?(@head_pair_abbrs, pair)
  def pair_abbr?(pair), do: MapSet.member?(@all_pair_abbrs, pair)
  def initial?(word), do: MapSet.member?(@initials, word)
end
