$(document).on('stonehearthReady', function(){
   App.discourseView = App.shellView.addView(App.DiscourseView);
});

App.DiscourseView = App.View.extend({
   classNames: [],
   templateName: 'discourseView',

   userAvatars: {},

   init: function() {
      this._super();
      var self = this;
      self._forceHidden = false;
   },

   didInsertElement: function() {
      let self = this;
      radiant.call('httplib:get_latest')
         .then(call => {
            let data = JSON.parse(call.result);
            data.topic_list.topics = data.topic_list.topics.slice(0, 20)
            // Turn this into a magic object of binding and happiness.
            // Also evil hacks. But happiness! Yaay! Happy!
            self.set('data', data);
            
            // Returns the user object for a certain user id.
            function findUser(id)
            {
               return data.users.find(user => user.id == id);
            }
            
            // For each topic, get the avatar of the latest user
            for (let i = 0; i < data.topic_list.topics.length; ++i)
            {
               let topic = data.topic_list.topics[i];
               // Get the user we're interested in. There's multiple ways in the JSON that it might be represented; we fall back to the latest poster.
               // Blame Discourse's API (or my lack to read it properly)
               let poster = topic.posters.find(p => (p.extras || "").match("latest")) || topic.posters[topic.posters.length - 1];
               let user = findUser(poster.user_id);

               if (!user)
                  continue;

               if (self.userAvatars[user.id] !== undefined)
                  continue;

               radiant.call('httplib:get_avatar', user.avatar_template.replace('{size}', '32'))
                  .then(call => {
                     // Deer Lord. (https://i.imgur.com/JrLJD9m.jpg)
                     let uri = 'data:image/' + (user.avatar_template.match(/.+\.(.+?)$/)[1]) + ';base64,' + call.result;
                     Ember.set(topic, 'user_avatar', uri); 
                  })
                  .fail(call => console.error('cannot fetch avatar:', call));
            }

            self._updateVisibility();
         })
         .fail(call => {
            // boo :(
         });

      $('#about').click(() => {
         self._forceHidden = !self._forceHidden;
         self._updateVisibility();
      });
   },

   _updateVisibility: function() {
      this.set('hide', this._forceHidden || !this.get('data'));
   }
});
