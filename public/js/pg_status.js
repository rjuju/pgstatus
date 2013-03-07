// This program is open source, licensed under the PostgreSQL Licence.
// For license terms, see the LICENSE file.

var refreshID = null;

function addQuery(database,pid){
  if ((database == '') || (pid == '')){
    return;
  }
  if ($('#pid'+pid).size() == 0){
    $('body').append('<div id="pid'+pid+'" class=container"></div>');
  }
  $.get('/pg_query/'+database+'/'+pid, function(data) {
    $('#pid'+pid).dialog({ title: "Detail of backend "+pid, height: 400, width: 1000}).html(data);
  });

}

function refreshStatus(){
  //$('#activity').fadeOut("slow").load('/pg_activity').fadeIn("slow");
  $('#activity tbody').load('/pg_activity');
  $("#activity").trigger("update"); 
  refreshCount();
}

function refreshCount(){
  $.ajax({
    url: "/pg_count/",
    type: "post",
    async: false,
    dataType: 'json',
  }).success(function(data){
    $('#count').html(data.count);
    $('#count_idle').html(data.count_idle);
    $('#count_idle_transaction').html(data.count_idle_transaction);
    $('#count_active').html(data.count_active);
    $('#count_waiting').html(data.count_waiting);
    $('#count_other').html(data.count_other);
  });
}

function toggleSetting(name){
  $.ajax({
    url: "/pg_toggle/"+name,
    type: "post",
    async: false}); 
	refreshStatus();
};

function displaySettings(){
  if ($('#settings').hasClass('hidden')){
    $('#settings').removeClass('hidden');
  } else{
    $('#settings').addClass('hidden');
  }
};

function cancelBackend(pid){
  $.ajax({
    url: "/pg_backend/"+pid+"/cancel",
    type: "post",
    async: false}); 
	refreshStatus();
};

function terminateBackend(pid){
  $.ajax({
    url: "/pg_backend/"+pid+"/terminate",
    type: "post",
    async: false}); 
	refreshStatus();
};

function toggleRefresh(){
  if (refreshID == null){
    refreshID = window.setInterval(refreshStatus, 1000);
  } else{
    window.clearInterval(refreshID);
    refreshID = null;
  }
}

$(document).ready(function(){
  $("#activity").tablesorter();
  refreshStatus();
  displaySettings();
  toggleRefresh();
  $('input[name=toggle_refresh]').attr('checked', (refreshID != null));
});
