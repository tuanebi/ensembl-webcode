/*
 * Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

(function($) {

  function obj_empty(x) {
    for(var k in x) {
      if(x.hasOwnProperty(k)) { return false; }
    }
    return true;
  }

  $.fn.new_table_filter = function(config,data,widgets) {

    var filterable_columns = {};

    function find_widget(wanted_name,type,def) {
      var w;
      $.each(widgets,function(name,contents) {
        if(contents[type]) {
          for(var i=0;i<contents[type].length;i++) {
            if(contents[type][i].name == wanted_name) {
              w = contents[type][i];
            }
          }
        }
      });
      if(w) { return w; }
      if(def!==null) { return find_widget(def,type,null); }
      return null;
    }

    function dropdown(idx,filter,label,primary) {
      var prec = primary?"pri":"sec";
      if(filter=='') { filter = 'more'; }
      return '<li class="t prec_'+prec+'" data-idx="'+idx+'"><span class="k">'+label+'</span><span class="v">All</span><div class="m newtable_filtertype_'+filter+'" data-filter="'+filter+'">'+label+'</div></li>';
    }

    function activate_menu($table,$button,others_only) {
      var $el = $button.find('.m');
      $('.newtable_filter li .m:visible').each(function() {
        if($el.length && $el[0] == this) { return; }
        hide_menu($(this));
      });
      if($button.length && !others_only) {
        if(!$el.is(":visible")) {
          menu($table,$button,$el);
          show_menu($el);
        } else {
          hide_menu($el);
        }
      }
    }

    function draw_more($table,$menu) {
      var $out = $("<ul/>");
      $('.newtable_filter .prec_sec.valid',$table).each(function() {
        var $item = $(this);
        var $li = $("<li/>").text($('.k',$item).text()).appendTo($out);
        $li.on('click',function(e) {
          $item.removeClass('prec_sec').addClass('prec_pri');
          activate_menu($table,$item,false);
          e.stopPropagation();
        });
      });
      $menu.empty().append($out);
    }

    function menu($table,$button,$menu) {
      var idx = $button.data('idx');
      if(idx==-1) {
        draw_more($table,$menu);
        return;
      }
      var key = config.columns[idx].key;
      var state = (($table.data('view').filter||{})[key])||{};
      var kind = config.colconf[key].range;
      var values = ($table.data('ranges')||{})[key];
      if(!values) { values = []; }
      var kparams = config.colconf[key].range_params;
      var w = find_widget(kind,'filters','class');
      w.display($menu,$button,values,state,kparams);
    }

    function show_or_hide_all($table) {
      var $filters = $('.newtable_filter',$table);
      var $vbuts = $('.t.valid',$filters);
      $filters.toggle(!!$vbuts.length);
    }

    function set_button($el,view,w,key,values) {
      $el.toggleClass('valid',!!w.visible(values));
      if(view.filter.hasOwnProperty(key)) {
        var text = w.text(view.filter[key],values);
        $('.v',$el).text(text);
      } else {
        $('.v',$el).text('All');
      }
    }

    function update_button($table,$el) {
      var view = $table.data('view');
      if(!view.filter) { view.filter = {}; }
      var idx = $el.data('idx');
      if(idx==-1) { // More button
        $el.addClass('more');
      } else { // Not more button
        var key = config.columns[idx].key;
        var values = ($table.data('ranges')||{})[key];
        var kind = config.colconf[key].range;
        var w = find_widget(kind,'filters','class');
        set_button($el,view,w,key,values);
        show_or_hide_all($table);
      }
      var $menu = $('.m',$el);
      if($menu.length && $menu.is(":visible")) {
        show_menu($menu);
      }
    }

    function update_state($table,$el,state) {
      var view = $table.data('view');
      if(!view.filter) { view.filter = {}; }
      var idx = $el.data('idx');
      var key = config.columns[idx].key;
      if(obj_empty(state)) {
        delete view.filter[key];
      } else {
        view.filter[key] = state;
      }
      if(obj_empty(view.filter)) { delete view.filter; }
      $table.data('view',view);
    }

    function show_menu($el) {
      $el.show();
      var right = $el.offset().left+$el.width();
      if(right>$('html').width()) {
        $el.css("left",($('html').width()-right-8)+"px");
      }
    }

    function hide_menu($el) {
      $el.hide();
    }

    return {
      generate: function() {
        var dropdowns = "";
        $.each(config.colconf,function(key,cc) {
          if(!cc.range) { return; }
          var label = "";
          var j = -1;
          for(var i=0;i<config.columns.length;i++) {
            if(config.columns[i].key == key) { j = i; break; }
          }
          var label = config.columns[j].label || config.columns[j].key;
          if(cc.range) {
            dropdowns += dropdown(j,cc.range,label,cc.primary);
            filterable_columns[key] = cc;
          }
        });
        dropdowns += dropdown(-1,'','More',true);

        var out='<div class="newtable_filter"><span class="intro">Filter</span><ul>'+dropdowns+'</ul></div>';
        return out;
      },
      go: function($table,$el) {
        var trigger_soon = $.debounce(function() {
          $table.trigger('view-updated');
        },5000);
        $('li.t',$el).on('update',function(e,state) {
          update_state($table,$(this),state);
          update_button($table,$(this));
          trigger_soon();
        });
        $table.on('range-updated',function(e) {
          $('li.t',$el).each(function() {
            var $button = $(this);
            update_button($table,$button);
            var $menu = $('.m',$button);
            if($menu.is(':visible')) {
              menu($table,$button,$menu);
              show_menu($menu);
            }
          });
        });
        $('li.t',$el).each(function() { update_button($table,$(this)); });
        $('html').on('click',function(e) {
          var $button = $(e.target).closest('.newtable_filter li.t');
          var $menu = $(e.target).closest('.newtable_filter li.t .m');
          activate_menu($table,$button,!!$menu.length);
        });
      },
      pipe: function() {
        return [
          function(need,got) {
            var server_filter = [];
            var client_enums = {};
            $.each(filterable_columns,function(key,cc) {
              var cf = find_widget(cc.enum_js,'enums',null);
              if(cf) {
                client_enums[key] = cf;
              } else {
                server_filter.push(key);
              }
            });
            need.enumerate = server_filter;
            return {
              eundo: function(enums,grid) {
                $.each(client_enums,function(col,plugin) {
                  for(var i=0;i<config.columns.length;i++) {
                    if(config.columns[i].key == col) {
                      var value = {};
                      for(var j=0;j<grid.length;j++) {
                        var v = grid[j][i];
                        if(v===null || v===undefined || v[1]) { continue; }
                        v = v[0];
                        if(plugin.split) {
                          v = plugin.split(v);
                        } else {
                          v = [v];
                        }
                        if(v===null || v===undefined) { continue; }
                        for(var k=0;k<v.length;k++) {
                          plugin.value(value,v[k]);
                        }
                      }
                      if(plugin.finish) { value = plugin.finish(value); }
                      enums[col] = value;
                    }
                  }
                });
                return enums;
              }
            };
          }
        ];
      }
    };
  }; 

})(jQuery);